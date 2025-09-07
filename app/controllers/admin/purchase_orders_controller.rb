class Admin::PurchaseOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_purchase_order, only: [:show, :edit, :update, :confirm_receipt, :destroy]
  before_action :load_counts, only: [:index]

  PER_PAGE = 20

  def index
    params[:status] ||= params[:current_status]
    @status_filter = params[:status].presence
    @q = params[:q].to_s.strip

  scope = PurchaseOrder.joins(:user).includes(:user)
  # Units per order (sum of item quantities) as items_count via subquery
  items_count_sql = "(SELECT COALESCE(SUM(quantity),0) FROM purchase_order_items poi WHERE poi.purchase_order_id = purchase_orders.id)"
  inv_count_sql   = "(SELECT COALESCE(COUNT(*),0) FROM inventories inv WHERE inv.purchase_order_id = purchase_orders.id)"
  scope = scope.select(
    "purchase_orders.*",
    "#{items_count_sql} AS items_count",
    "#{inv_count_sql} AS inventory_count",
    "(#{items_count_sql} - #{inv_count_sql}) AS remaining_count"
  )
  # Sorting
  sort = params[:sort].presence
  dir  = params[:dir].to_s.downcase == 'asc' ? 'asc' : 'desc'
  sort_map = {
    'supplier'     => 'users.name',
    'date'         => 'purchase_orders.order_date',
    'expected'     => 'purchase_orders.expected_delivery_date',
  'total_mxn'    => 'purchase_orders.total_cost_mxn',
  'items'        => 'items_count',
  'remaining'    => 'remaining_count',
    'created'      => 'purchase_orders.created_at'
  }
  if sort_map.key?(sort)
    scope = scope.order(Arel.sql("#{sort_map[sort]} #{dir.upcase}"))
  else
    scope = scope.order(created_at: :desc)
  end
  if @status_filter.present? && @status_filter != "all"
      scope = scope.where(status: @status_filter)
    end
    if @q.present?
      adapter = ActiveRecord::Base.connection.adapter_name.downcase
      id_cast = adapter.include?("postgres") ? "purchase_orders.id::text" : "CAST(purchase_orders.id AS TEXT)"
      name_cond = adapter.include?("postgres") ? "users.name ILIKE ?" : "LOWER(users.name) LIKE ?"
      term = adapter.include?("postgres") ? "%#{@q}%" : "%#{@q.downcase}%"
      if (m = @q.match(/\A#?(\d+)\z/))
        # Búsqueda directa por ID exacto (permite prefijo opcional #)
        exact_id = m[1].to_i
        scope = scope.where(["purchase_orders.id = ? OR #{name_cond}", exact_id, term])
      else
        scope = scope.where(["#{id_cast} LIKE ? OR #{name_cond}", term, term])
      end
    end
  # Dataset para exportación (sin paginar)
  @export_purchase_orders = scope
  @purchase_orders = scope.page(params[:page]).per(PER_PAGE)

  counts_scope = PurchaseOrder.joins(:user)
    if @q.present?
      adapter = ActiveRecord::Base.connection.adapter_name.downcase
      id_cast = adapter.include?("postgres") ? "purchase_orders.id::text" : "CAST(purchase_orders.id AS TEXT)"
      name_cond = adapter.include?("postgres") ? "users.name ILIKE ?" : "LOWER(users.name) LIKE ?"
      term = adapter.include?("postgres") ? "%#{@q}%" : "%#{@q.downcase}%"
      if (m = @q.match(/\A#?(\d+)\z/))
        exact_id = m[1].to_i
        counts_scope = counts_scope.where(["purchase_orders.id = ? OR #{name_cond}", exact_id, term])
      else
        counts_scope = counts_scope.where(["#{id_cast} LIKE ? OR #{name_cond}", term, term])
      end
    end
    statuses = ["Pending", "In Transit", "Delivered", "Canceled"]
    # Superiores (globales)
    @counts_global = statuses.each_with_object({}) { |s, h| h[s] = PurchaseOrder.where(status: s).count }
    # Inferiores (filtrados por q y status)
    filtered = counts_scope
    if @status_filter.present? && @status_filter != "all"
      filtered = filtered.where(status: @status_filter)
    end
    @counts = statuses.each_with_object({}) { |s, h| h[s] = filtered.where(status: s).count }
    respond_to do |format|
      format.html
      format.csv { send_data csv_for_purchase_orders(@export_purchase_orders), filename: "purchase_orders-#{Time.current.strftime('%Y%m%d-%H%M')}.csv" }
      format.any  { head :not_acceptable }
    end
  end

  def show
  # Auditoría: conteo ESTRICTO por línea (purchase_order_item_id)
  scope = Inventory.where(purchase_order_id: @purchase_order.id)
  @inventory_counts_by_line = scope.where.not(purchase_order_item_id: nil)
                   .group(:purchase_order_item_id)
                   .count
  # Desglose de estados por línea (para tooltip)
  @inventory_status_counts_by_line = scope.where.not(purchase_order_item_id: nil)
                      .group(:purchase_order_item_id, :status)
                      .count
  # Mapa para traducir enum status numérico a nombre
  @inventory_status_names = Inventory.statuses.invert

    # Resumen superior: líneas, total ordenado, inventario generado y restante
    lines_count   = @purchase_order.purchase_order_items.size
    ordered_units = @purchase_order.purchase_order_items.sum(:quantity)
    generated_inv = scope.count
    remaining     = [ordered_units - generated_inv, 0].max
    @po_summary = {
      lines: lines_count,
      ordered: ordered_units,
      generated: generated_inv,
      remaining: remaining
    }
  end

  def new
    @purchase_order = PurchaseOrder.new(order_date: Date.today)
  end

  def create
    @purchase_order = PurchaseOrder.new(purchase_order_params)

    if @purchase_order.save
      redirect_to admin_purchase_orders_path, notice: "Purchase order created successfully."
    else
      flash.now[:alert] = @purchase_order.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @purchase_order.update(purchase_order_params)
      redirect_to admin_purchase_orders_path, notice: "Purchase order updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @purchase_order = PurchaseOrder.find(params[:id])

    if @purchase_order.destroy
      redirect_to admin_purchase_orders_path, notice: "Purchase order eliminada."
    else
      redirect_to admin_purchase_order_path(@purchase_order),
        alert: @purchase_order.errors.full_messages.to_sentence.presence || "No se pudo eliminar."
    end
  end

  def confirm_receipt
    if @purchase_order.status == "In Transit"
  # Solo cambia el estado de la PO; el modelo se encargará de mover inventario
  @purchase_order.update!(status: "Delivered")
      flash[:notice] = "Recepción confirmada. Inventario actualizado."
    else
      flash[:alert] = "Solo se pueden confirmar órdenes 'In Transit'."
    end
    redirect_to admin_purchase_order_path(@purchase_order)
  end

  # Corrige inventario para una PO: ajusta por línea para que COUNT(inv) == quantity
  def rebalance_inventory
    po = PurchaseOrder.find(params[:id])
    lines = po.purchase_order_items.includes(:product)
  created_total = 0
  deleted_total = 0
    lines.each do |li|
      desired = li.quantity.to_i
      scope = Inventory.where(purchase_order_item_id: li.id)
      current = scope.count
      diff = desired - current
      if diff > 0
        diff.times do
          Inventory.create!(
            product_id: li.product_id,
            purchase_order_id: po.id,
            purchase_order_item_id: li.id,
            status: (po.status.in?(["Pending","In Transit"]) ? :in_transit : :available),
            status_changed_at: Time.current,
            purchase_cost: li.unit_compose_cost_in_mxn.to_f
          )
        end
    created_total += diff
      elsif diff < 0
    destroyed = scope.where(status: [:available, :in_transit], sale_order_id: nil)
             .order(status_changed_at: :desc)
             .limit(diff.abs)
             .destroy_all
             .size
    deleted_total += destroyed
      end
    end
  redirect_to admin_purchase_order_path(po), notice: "Rebalanceo completado. Creadas: #{created_total}. Eliminadas: #{deleted_total}."
  end

  # Corrige en lote todas las líneas con desajuste (según auditoría)
  def rebalance_all_mismatches
    dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run])

    mismatches = PurchaseOrderItem
      .joins("LEFT JOIN inventories inv ON inv.purchase_order_item_id = purchase_order_items.id")
      .select('purchase_order_items.id')
      .group('purchase_order_items.id')
      .having('COUNT(inv.id) <> purchase_order_items.quantity')

    ids = mismatches.pluck(:id)

    # Acumuladores
    created_planned = 0
    planned_available = 0
    planned_in_transit = 0
    deletions_planned = 0
    deletions_possible = 0

    created_done = 0
    deleted_done = 0

    PurchaseOrderItem.where(id: ids).includes(:purchase_order).find_each do |li|
      po = li.purchase_order
      desired = li.quantity.to_i
      scope = Inventory.where(purchase_order_item_id: li.id)
      current = scope.count
      diff = desired - current

      if diff > 0
        status_sym = (po.status.in?( ["Pending","In Transit"] ) ? :in_transit : :available)
        created_planned += diff
        if status_sym == :in_transit
          planned_in_transit += diff
        else
          planned_available += diff
        end
        unless dry_run
          diff.times do
            Inventory.create!(
              product_id: li.product_id,
              purchase_order_id: po.id,
              purchase_order_item_id: li.id,
              status: status_sym,
              status_changed_at: Time.current,
              purchase_cost: li.unit_compose_cost_in_mxn.to_f
            )
          end
          created_done += diff
        end
      elsif diff < 0
        deletions_planned += diff.abs
        deletable_scope = scope.where(status: [:available, :in_transit], sale_order_id: nil)
        available_to_delete = deletable_scope.count
        deletions_possible += [available_to_delete, diff.abs].min
        unless dry_run
          destroyed_count = deletable_scope.order(status_changed_at: :desc)
                                          .limit(diff.abs)
                                          .destroy_all
                                          .size
          deleted_done += destroyed_count
        end
      end
    end

    if dry_run
      msg = "Simulación: crear #{created_planned} (available #{planned_available}, in_transit #{planned_in_transit}); " \
            "eliminar hasta #{deletions_possible} de #{deletions_planned} planeadas (solo available/in_transit sin SO)."
      redirect_to line_audit_admin_purchase_orders_path, notice: msg
    else
      msg = "Rebalanceo masivo completado. Creadas: #{created_done}. Eliminadas: #{deleted_done}."
      redirect_to line_audit_admin_purchase_orders_path, notice: msg
    end
  end

  # Auditoría: POs con líneas cuyos restos > 0 (Qty - inventario generado por línea)
  def line_audit
    # Buscar líneas con desajuste
    mismatches = PurchaseOrderItem
      .joins("LEFT JOIN inventories inv ON inv.purchase_order_item_id = purchase_order_items.id")
      .select(
        'purchase_order_items.*',
        'COUNT(inv.id) AS generated_count'
      )
      .group('purchase_order_items.id')
      .having('COUNT(inv.id) <> purchase_order_items.quantity')

    @lines_with_mismatch = mismatches.includes(:product, :purchase_order).order('purchase_order_items.purchase_order_id DESC')

    # POs con SKUs repetidos (potencial fuente del problema)
    @pos_with_duplicate_skus = PurchaseOrderItem
      .select('purchase_order_id, product_id, COUNT(*) as line_count')
      .group('purchase_order_id, product_id')
      .having('COUNT(*) > 1')
      .order('purchase_order_id DESC, line_count DESC')
  end

  private

  def set_purchase_order
    @purchase_order = PurchaseOrder.includes(:purchase_order_items).find(params[:id])
  end

  def purchase_order_params
    params.require(:purchase_order).permit(
      :user_id, :order_date, :expected_delivery_date,
      :subtotal, :tax_cost, :currency, :shipping_cost,
      :other_cost, :discount, :status, :notes, :total_cost, :total_cost_mxn,
      :actual_delivery_date, :exchange_rate, :total_order_cost, :total_volume, :total_weight,
      purchase_order_items_attributes: [:id, :product_id, :quantity, :unit_cost,
      :unit_additional_cost, :unit_compose_cost, :unit_compose_cost_in_mxn, :total_line_cost, :total_line_volume,
      :total_line_weight, :total_line_cost_in_mxn, :_destroy]
    )
  end

  def load_counts
  @counts ||= PurchaseOrder.group(:status).count
  end

  def csv_for_purchase_orders(relation)
    require 'csv'
    CSV.generate(headers: true) do |csv|
      csv << [
        "ID", "Supplier", "Order Date", "Expected Delivery", "Status",
        "Items", "Currency", "Total Cost", "Total Cost MXN", "Total Weight", "Total Volume"
      ]
      relation.each do |po|
        csv << [
          po.id,
          po.user&.name,
          po.order_date,
          po.expected_delivery_date,
          po.status,
          po.attributes["items_count"].to_i,
          po.currency,
          po.total_order_cost,
          po.total_cost_mxn,
          po.total_weight,
          po.total_volume
        ]
      end
    end
  end

  # XLSX export removed
end
