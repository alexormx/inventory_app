# app/controllers/admin/sale_orders_controller.rb
class Admin::SaleOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_sale_order, only: %i[show edit update destroy]
  before_action :load_counts, only: [:index]

  PER_PAGE = 20

  def index
    # Filtros y búsqueda similares a inventario
    params[:status] ||= params[:current_status]
    @status_filter = params[:status].presence
    @q = params[:q].to_s.strip

  scope = SaleOrder.joins(:user).includes(:user)
    # Sorting
    sort = params[:sort].presence
    dir  = params[:dir].to_s.downcase == 'asc' ? 'asc' : 'desc'
    sort_map = {
      'date'      => 'sale_orders.order_date',
      'created'   => 'sale_orders.created_at',
      'customer'  => 'users.name',
      'total_mxn' => 'sale_orders.total_order_value'
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
      scope = scope.where("CAST(sale_orders.id AS TEXT) LIKE ? OR LOWER(users.name) LIKE ?", term, term)
    end
  @sale_orders = scope.page(params[:page]).per(PER_PAGE)

    # Contadores superiores (globales) e inferiores (filtrados)
    statuses = ["Pending", "Confirmed", "Shipped", "Delivered", "Canceled"]
    @counts_global = statuses.each_with_object({}) { |s, h| h[s] = SaleOrder.where(status: s).count }
    counts_scope = SaleOrder.joins(:user)
    if @q.present?
      term = "%#{@q.downcase}%"
      counts_scope = counts_scope.where("CAST(sale_orders.id AS TEXT) LIKE ? OR LOWER(users.name) LIKE ?", term, term)
    end
    if @status_filter.present? && @status_filter != "all"
      counts_scope = counts_scope.where(status: @status_filter)
    end
    @counts = statuses.each_with_object({}) { |s, h| h[s] = counts_scope.where(status: s).count }
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
    if @sale_order.destroy
      redirect_to admin_sale_orders_path, notice: "Sale order eliminada."
    else
      redirect_to admin_sale_order_path(@sale_order),
        alert: @sale_order.errors.full_messages.to_sentence.presence || "No se pudo eliminar la orden."
    end
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
end

