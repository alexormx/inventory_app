# frozen_string_literal: true
# rubocop:disable all

# app/controllers/admin/sale_orders_controller.rb
class Admin::SaleOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_sale_order, only: %i[show edit update destroy summary cancel]
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
    if @sale_order.update(sale_order_params)
      @sale_order.update_status_if_fully_paid!
      redirect_to admin_sale_order_path(@sale_order), notice: "Sale order updated successfully"
    else
      flash.now[:alert] = "There were errors saving the sale order"
      render :edit, status: :unprocessable_entity
    end
  end

  def show; end

  def destroy
    redirect_to admin_sale_order_path(@sale_order), alert: "La eliminación está deshabilitada. Usa Cancelar para liberar inventario y dejarla sin efecto."
  end

  def cancel
    SaleOrders::CancelOrderService.new(@sale_order).call
    redirect_to admin_sale_order_path(@sale_order),
                notice: "Orden cancelada exitosamente. Inventarios liberados y disponibles."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_sale_order_path(@sale_order),
                alert: "No se pudo cancelar la orden: #{e.message}"
  end

  # Admin compact summary view: reuse customer summary template but under admin layout
  # This avoids duplication while preserving styling/structure improvements already applied there.
  def summary
    @order = @sale_order # variable name expected by shared summary template
    render 'orders/summary'
  end

  private

  def set_sale_order
    @sale_order = SaleOrder.find_by!(id: params[:id])
  end

  def sale_order_params
    params.require(:sale_order).permit(
      :user_id, :order_date, :subtotal, :tax_rate,
      :total_tax, :total_order_value, :discount,
      :status, :notes,
      # Credit fields
      :credit_override, :credit_terms,
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

# rubocop:enable all

