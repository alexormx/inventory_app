# frozen_string_literal: true

class OrdersController < ApplicationController
  before_action :authenticate_user!
  # Forzar siempre layout cliente incluso si el usuario es admin (modo self-service)
  layout 'customer'

  def index
    @orders = current_user.sale_orders.includes(:payments).order(created_at: :desc)
    @item_counts = SaleOrderItem.where(sale_order_id: @orders.map(&:id)).group(:sale_order_id).sum(:quantity)
  end

  # Una sola vista de pedido (la antigua "compacta"); /summary se conserva
  # para que los enlaces viejos sigan funcionando.
  def show
    @order = find_order
  end

  def summary
    @order = find_order
    render :show
  end

  private

  def find_order
    current_user.sale_orders
                .includes(:payments, :shipment, :order_shipping_address,
                          sale_order_items: [:inventory_units, { product: { product_images_attachments: :blob } }])
                .find(params[:id])
  end

  # Nota: No se restringe a admins; pueden ver sus propios pedidos en vista cliente.
end
