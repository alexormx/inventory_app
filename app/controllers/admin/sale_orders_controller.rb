# app/controllers/admin/sales_orders_controller.rb
class Admin::SaleOrdersController < ApplicationController
  before_action :set_sale_order, only: %i[show edit update destroy]

  def index
    @sale_orders = SaleOrder.includes(:user).order(created_at: :desc)
  end

  def new
    @sale_order = SaleOrder.new(order_date: Date.today)
  end

  def create
    @sale_order = SaleOrder.new(sale_order_params)
    if @sale_order.save
      redirect_to admin_sale_order_path(@sale_order), notice: "Sale order created"
    else
      render :new
    end
  end

  def edit; end

  def update
    if @sale_order.update(sale_order_params)
      redirect_to admin_sale_order_path(@sale_order), notice: "Sale order updated"
    else
      render :edit
    end
  end

  def show; end

  def destroy
    @sale_order.destroy
    redirect_to admin_sale_orders_path, alert: "Sale order deleted"
  end

  private

  def set_sale_order
    @sale_order = SaleOrder.find_by!(id: params[:id])
  end

  def sals_order_params
    params.require(:sale_order).permit(:user_id, :order_date, :status, :notes, :discount, :subtotal, :tax_rate, :total_tax, :total_order_value)
  end
end
