class Admin::PurchaseOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_purchase_order, only: [:show, :edit, :update, :confirm_receipt, :destroy]
  before_action :load_counts, only: [:index]

  PER_PAGE = 20

  def index
    @purchase_orders = PurchaseOrder.order(created_at: :desc).page(params[:page]).per(PER_PAGE)
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
    @counts = PurchaseOrder.group(:status).count
  end
end
