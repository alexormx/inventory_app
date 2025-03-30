class Admin::PurchaseOrdersController < ApplicationController
  before_action :authorize_admin!

  def index
    @purchase_orders = PurchaseOrder.all
  end

  def show
    @purchase_order = PurchaseOrder.find(params[:id])
  end

  def new
    @purchase_order = PurchaseOrder.new(order_date: Date.today)
  end
  
  def create
    @purchase_order = PurchaseOrder.new(purchase_order_params)
  
    if @purchase_order.save
      redirect_to admin_purchase_orders_path, notice: "Purchase order created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @purchase_order = PurchaseOrder.includes(:purchase_order_items).find(params[:id])
  end
  
  def update
    @purchase_order = PurchaseOrder.find(params[:id])
    if @purchase_order.update(purchase_order_params)
      redirect_to admin_purchase_orders_path, notice: "Purchase order updated successfully."
    else
      render :edit
    end
  end

  def confirm_receipt
    @purchase_order = PurchaseOrder.find(params[:id])
    if @purchase_order.update(status: "Delivered")
      flash[:notice] = "Recepción confirmada. Inventario actualizado."
    else
      flash[:alert] = "No se pudo confirmar la recepción."
    end
    redirect_to admin_purchase_order_path(@purchase_order)
  end

  private

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
end
