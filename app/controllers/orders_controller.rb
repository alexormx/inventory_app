class OrdersController < ApplicationController
  before_action :authenticate_user!
  layout "customer"

  def index
    @orders = current_user.sale_orders.order(created_at: :desc)
  end

  def show
    @order = current_user.sale_orders.find(params[:id])
  end
end