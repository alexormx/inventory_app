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
  scope = scope.select("purchase_orders.*", "(SELECT COALESCE(SUM(quantity),0) FROM purchase_order_items poi WHERE poi.purchase_order_id = purchase_orders.id) AS items_count")
  # Sorting
  sort = params[:sort].presence
  dir  = params[:dir].to_s.downcase == 'asc' ? 'asc' : 'desc'
  sort_map = {
    'supplier'     => 'users.name',
    'date'         => 'purchase_orders.order_date',
    'expected'     => 'purchase_orders.expected_delivery_date',
  'total_mxn'    => 'purchase_orders.total_cost_mxn',
  'items'        => 'items_count',
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
      term = "%#{@q.downcase}%"
      scope = scope.where("CAST(purchase_orders.id AS TEXT) LIKE ? OR LOWER(users.name) LIKE ?", term, term)
    end
  @purchase_orders = scope.page(params[:page]).per(PER_PAGE)

  counts_scope = PurchaseOrder.joins(:user)
    if @q.present?
      term = "%#{@q.downcase}%"
      counts_scope = counts_scope.where("CAST(purchase_orders.id AS TEXT) LIKE ? OR LOWER(users.name) LIKE ?", term, term)
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
  end

  def show
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
      Inventory.where(purchase_order_id: @purchase_order.id).in_transit.update_all(
        status: :available,
        updated_at: Time.current,
        status_changed_at: Time.current
      )
      @purchase_order.update!(status: "Delivered")
      flash[:notice] = "Recepción confirmada. Inventario actualizado."
    else
      flash[:alert] = "Solo se pueden confirmar órdenes 'In Transit'."
    end
    redirect_to admin_purchase_order_path(@purchase_order)
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
end
