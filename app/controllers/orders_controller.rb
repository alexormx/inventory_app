class OrdersController < ApplicationController
  before_action :authenticate_user!
  layout "customer"

  def index
    @orders = current_user.sale_orders.order(created_at: :desc)
  end

  def show
    @order = current_user.sale_orders.find(params[:id])
  end

  # Vista resumida para enviar totales (sin toda la metadata interna)
  def summary
    @order = current_user.sale_orders.includes(:payments, :shipment, sale_order_items: [product: [product_images_attachments: :blob]]).find(params[:id])
  end
end