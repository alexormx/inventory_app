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

  private

  def purchase_order_params
    params.require(:purchase_order).permit(
      :user_id, :order_date, :expected_delivery_date,
      :subtotal, :tax_cost, :currency, :shipping_cost,
      :other_cost, :discount, :status, :notes, :total_cost, :total_cost_mxn,
      :actual_delivery_date, :exchange_rate, :total_order_cost
    )

  end
end
