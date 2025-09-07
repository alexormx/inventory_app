# app/controllers/admin/sale_orders_controller.rb
class Admin::SaleOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_sale_order, only: %i[show edit update destroy cancel_reservations reassign export_cancellations]
  before_action :set_sale_order_with_includes, only: %i[summary]
  before_action :load_counts, only: [:index]

  PER_PAGE = 20

  def index
    # Filtros y búsqueda similares a inventario
    params[:status] ||= params[:current_status]
    @status_filter = params[:status].presence
  @q = params[:q].to_s.strip
  # Filtro: con adeudo (balance > 0)
  @due_filter = %w[1 true yes on].include?(params[:due].to_s)

  scope = SaleOrder.joins(:user).includes(:user)
  # Subqueries: items_count, total_paid (pagos Completed), balance_due
  items_count_sql = "(SELECT COALESCE(SUM(quantity),0) FROM sale_order_items soi WHERE soi.sale_order_id = sale_orders.id) AS items_count"
  total_paid_sql  = "(SELECT COALESCE(SUM(amount),0) FROM payments p WHERE p.sale_order_id = sale_orders.id AND p.status = 'Completed') AS total_paid_value"
  balance_due_sql = "(sale_orders.total_order_value - (SELECT COALESCE(SUM(amount),0) FROM payments p2 WHERE p2.sale_order_id = sale_orders.id AND p2.status = 'Completed')) AS balance_due_value"
  scope = scope.select("sale_orders.*", items_count_sql, total_paid_sql, balance_due_sql)
    # Sorting
    sort = params[:sort].presence
    dir  = params[:dir].to_s.downcase == 'asc' ? 'asc' : 'desc'
    sort_map = {
      'date'      => 'sale_orders.order_date',
      'created'   => 'sale_orders.created_at',
      'customer'  => 'users.name',
  'total_mxn' => 'sale_orders.total_order_value',
  'items'     => 'items_count',
      'paid'      => 'total_paid_value',
      'balance'   => 'balance_due_value'
    }
    if sort_map.key?(sort)
      scope = scope.order(Arel.sql("#{sort_map[sort]} #{dir.upcase}"))
    else
      scope = scope.order(created_at: :desc)
    end
    if @status_filter.present? && @status_filter != "all"
      scope = scope.where(status: @status_filter)
    end
    if @due_filter
      balance_expr = "sale_orders.total_order_value - (SELECT COALESCE(SUM(amount),0) FROM payments p2 WHERE p2.sale_order_id = sale_orders.id AND p2.status = 'Completed')"
      scope = scope.where(Arel.sql("#{balance_expr} > 0"))
    end
    if @q.present?
      adapter = ActiveRecord::Base.connection.adapter_name.downcase
      id_cast = adapter.include?("postgres") ? "sale_orders.id::text" : "CAST(sale_orders.id AS TEXT)"
      name_cond = adapter.include?("postgres") ? "users.name ILIKE ?" : "LOWER(users.name) LIKE ?"
      term = adapter.include?("postgres") ? "%#{@q}%" : "%#{@q.downcase}%"
      if (m = @q.match(/\A#?(\d+)\z/))
        exact_id = m[1].to_i
        scope = scope.where(["sale_orders.id = ? OR #{name_cond}", exact_id, term])
      else
        scope = scope.where(["#{id_cast} LIKE ? OR #{name_cond}", term, term])
      end
    end
  # Dataset para exportación (sin paginar)
  @export_sale_orders = scope
  @sale_orders = scope.page(params[:page]).per(PER_PAGE)

    # Contadores superiores (globales) e inferiores (filtrados)
    statuses = ["Pending", "Confirmed", "Shipped", "Delivered", "Canceled"]
    @counts_global = statuses.each_with_object({}) { |s, h| h[s] = SaleOrder.where(status: s).count }
  counts_scope = SaleOrder.joins(:user)
    if @q.present?
      adapter = ActiveRecord::Base.connection.adapter_name.downcase
      id_cast = adapter.include?("postgres") ? "sale_orders.id::text" : "CAST(sale_orders.id AS TEXT)"
      name_cond = adapter.include?("postgres") ? "users.name ILIKE ?" : "LOWER(users.name) LIKE ?"
      term = adapter.include?("postgres") ? "%#{@q}%" : "%#{@q.downcase}%"
      if (m = @q.match(/\A#?(\d+)\z/))
        exact_id = m[1].to_i
        counts_scope = counts_scope.where(["sale_orders.id = ? OR #{name_cond}", exact_id, term])
      else
        counts_scope = counts_scope.where(["#{id_cast} LIKE ? OR #{name_cond}", term, term])
      end
    end
  if @status_filter.present? && @status_filter != "all"
      counts_scope = counts_scope.where(status: @status_filter)
    end
  # Nota: los contadores por status no aplican 'due', se mantienen globales al filtro de status/búsqueda.
    @counts = statuses.each_with_object({}) { |s, h| h[s] = counts_scope.where(status: s).count }
    respond_to do |format|
      format.html
      format.csv { send_data csv_for_sale_orders(@export_sale_orders), filename: "sale_orders-#{Time.current.strftime('%Y%m%d-%H%M')}.csv" }
      format.any  { head :not_acceptable }
    end
  end

  def new
    @sale_order = SaleOrder.new(order_date: Date.today)
  end

  def create
    @sale_order = SaleOrder.new(sale_order_params)
    if @sale_order.save
      @sale_order.update_status_if_fully_paid! # If you want to trigger status logic
      redirect_to admin_sale_order_path(@sale_order), notice: "Sale order created"
    else
      Rails.logger.error(@sale_order.errors.full_messages)
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @sale_order = SaleOrder.find(params[:id])
    begin
      if @sale_order.update(sale_order_params)
        @sale_order.update_status_if_fully_paid!
        redirect_to admin_sale_order_path(@sale_order), notice: "Sale order updated successfully"
      else
        flash.now[:alert] = "There were errors saving the sale order"
        render :edit, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotDestroyed => e
      # Caso común: intento de eliminar una línea con unidades ya vendidas
      msg = e.record&.errors&.full_messages&.to_sentence.presence ||
            "No se pudo eliminar una línea. Verifique que no tenga unidades vendidas."

      # Intentar una recuperación parcial: liberar unidades reservadas de esa línea y reasignar a preventas
      if (soi = e.record).present?
        begin
          freed = Inventory.where(sale_order_id: soi.sale_order_id, product_id: soi.product_id, status: Inventory.statuses[:reserved])
                           .update_all(status: Inventory.statuses[:available], sale_order_id: nil, sale_order_item_id: nil, status_changed_at: Time.current, updated_at: Time.current)
          if freed.to_i > 0
            Rails.logger.info("[SaleOrders#update] Liberadas #{freed} piezas reservadas de la línea #{soi.id} tras fallo de destrucción")
            begin
              Preorders::PreorderAllocator.new(soi.product).call
            rescue => alloc_err
              Rails.logger.error("[SaleOrders#update] Error al asignar preventas tras liberar: #{alloc_err.class} #{alloc_err.message}")
            end
          end
        rescue => free_err
          Rails.logger.error("[SaleOrders#update] Error al liberar reservados tras fallo de destrucción: #{free_err.class} #{free_err.message}")
        end
      end

      Rails.logger.warn("[SaleOrders#update] RecordNotDestroyed: #{msg}")
      flash.now[:alert] = msg
      @sale_order.reload
      render :edit, status: :unprocessable_entity
    end
  end

  def show; end

  # Cancelación manual de reservas antiguas por SO (sin tocar vendidos)
  def cancel_reservations
    reason = params[:reason].to_s.presence || "Cancelación manual de reservas antiguas"
    # No permitir cancelar en Confirmed o Delivered
    if ["Confirmed", "Delivered"].include?(@sale_order.status)
      return redirect_to admin_sale_order_path(@sale_order), alert: "No puedes cancelar reservas de una orden Confirmed o Delivered."
    end
    result = ::SaleOrders::CancelOldReservations.new(sale_order: @sale_order, reason: reason, actor: current_user).call
    if result.ok
      redirect_to admin_sale_order_path(@sale_order), notice: "Reservas canceladas: liberadas=#{result.released_units}, preventas canceladas=#{result.preorders_cancelled}."
    else
      redirect_to admin_sale_order_path(@sale_order), alert: (result.errors&.to_sentence || "Error al cancelar reservas")
    end
  end

  # Reasigna inventario a una SO cancelada, siguiendo el flujo de una nueva SO
  def reassign
    if @sale_order.status != 'Canceled'
      return redirect_to admin_sale_order_path(@sale_order), alert: 'Solo puedes reasignar cuando la orden está en estado Canceled.'
    end
    begin
      # Intentar asignar available primero y luego in_transit como pre_*
      @sale_order.sale_order_items.includes(:product).find_each do |li|
        needed = li.quantity.to_i
        # contar ya asignados (por si quedaron)
        assigned = Inventory.where(sale_order_id: @sale_order.id, product_id: li.product_id, status: [:reserved, :sold, :pre_reserved, :pre_sold]).count
        remaining = needed - assigned
        next if remaining <= 0

        # 1) available -> reserved
        avail = Inventory.where(product_id: li.product_id, status: :available, sale_order_id: nil).order(:status_changed_at).limit(remaining).to_a
        avail.each do |inv|
          inv.update!(status: :reserved, sale_order_id: @sale_order.id, sale_order_item_id: li.id, status_changed_at: Time.current, sold_price: li.unit_final_price.to_f.nonzero? || inv.sold_price)
        end
        remaining -= avail.size

        # 2) in_transit -> pre_reserved (o pre_sold si decides confirmar después con pago)
        if remaining > 0
          it = Inventory.where(product_id: li.product_id, status: :in_transit, sale_order_id: nil).order(:status_changed_at).limit(remaining).to_a
          it.each do |inv|
            inv.update!(status: :pre_reserved, sale_order_id: @sale_order.id, sale_order_item_id: li.id, status_changed_at: Time.current, sold_price: li.unit_final_price.to_f.nonzero? || inv.sold_price)
          end
          remaining -= it.size
        end

        # 3) Si aún falta, crear preventa pendiente
        if remaining > 0
          PreorderReservation.create!(product_id: li.product_id, user_id: @sale_order.user_id, sale_order_id: @sale_order.id, quantity: remaining, status: :pending, reserved_at: Time.current)
          li.update_columns(preorder_quantity: li.preorder_quantity.to_i + remaining, updated_at: Time.current)
        end
      end
      # Poner status a Pending para indicar que necesita confirmación/pago antes de entregar
      @sale_order.update!(status: 'Pending')
      redirect_to admin_sale_order_path(@sale_order), notice: 'Reasignación completada. La orden quedó en Pending.'
    rescue => e
      redirect_to admin_sale_order_path(@sale_order), alert: "Error al reasignar: #{e.message}"
    end
  end

  # Vista compacta de totales/costos para compartir con cliente
  def summary
    # @sale_order cargada con includes para evitar N+1
    respond_to do |format|
      format.html { render :summary }
      format.pdf do
        # Placeholder: se podría integrar gem wicked_pdf/prawn más adelante
        render :summary, layout: "pdf"
      end
    end
  end

  def destroy
    if @sale_order.destroy
      redirect_to admin_sale_orders_path, notice: "Sale order eliminada."
    else
      redirect_to admin_sale_order_path(@sale_order),
        alert: @sale_order.errors.full_messages.to_sentence.presence || "No se pudo eliminar la orden."
    end
  end

  # Exporta CSV de cancelaciones de esta SO
  def export_cancellations
    items = CanceledOrderItem.where(sale_order_id: @sale_order.id).includes(:product)
    require 'csv'
    csv = CSV.generate(headers: true) do |out|
      out << ["Sale Order", "Product SKU", "Product Name", "Canceled Qty", "Unit Price at Cancel", "Reason", "Canceled At"]
      items.find_each do |it|
        out << [
          it.sale_order_id,
          it.product&.product_sku,
          it.product&.product_name,
          it.canceled_quantity,
          it.sale_price_at_cancellation,
          it.cancellation_reason,
          it.canceled_at&.to_s(:db)
        ]
      end
    end
    send_data csv, filename: "cancellations-#{@sale_order.id}-#{Time.current.strftime('%Y%m%d-%H%M')}.csv", type: 'text/csv'
  end

  private

  def set_sale_order
    @sale_order = SaleOrder.find_by!(id: params[:id])
  end

  def set_sale_order_with_includes
    @sale_order = SaleOrder.includes(:payments, :shipment, sale_order_items: [product: [product_images_attachments: :blob]]).find(params[:id])
  end

  def sale_order_params
    params.require(:sale_order).permit(
      :user_id, :order_date, :subtotal, :tax_rate,
      :total_tax, :total_order_value, :discount,
      :status, :notes,
      sale_order_items_attributes: [
        :id, :product_id, :quantity, :unit_cost, :unit_discount,
        :unit_final_price, :total_line_cost, :total_line_volume,
        :total_line_weight, :_destroy
      ]
    )
  end

  def load_counts
    # Mantener método para compatibilidad; @counts se recalcula en index
    @counts ||= SaleOrder.group(:status).count
  end

  def csv_for_sale_orders(relation)
    require 'csv'
    CSV.generate(headers: true) do |csv|
      csv << [
        "ID", "Customer", "Order Date", "Status", "Items", "Total", "Pagado", "Adeudo", "Discount"
      ]
      relation.each do |so|
        csv << [
          so.id,
          so.user&.name,
          so.order_date,
          so.status,
          so.attributes["items_count"].to_i,
          so.total_order_value,
          so.attributes["total_paid_value"].to_d,
          so.attributes["balance_due_value"].to_d,
          so.discount
        ]
      end
    end
  end

  # XLSX export removed
end

