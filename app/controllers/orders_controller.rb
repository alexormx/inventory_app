# frozen_string_literal: true

class OrdersController < ApplicationController
  before_action :authenticate_user!
  # Forzar siempre layout cliente incluso si el usuario es admin (modo self-service)
  layout 'customer'

  def index
    @orders = current_user.sale_orders.order(created_at: :desc)
  end

  def show
    @order = find_order
  end

  def summary
    @order = find_order
    # layout ya forzado a 'customer'
    render :summary
  end

  private

  def find_order
    current_user.sale_orders.find(params[:id])
  end

  # Nota: No se restringe a admins; pueden ver sus propios pedidos en vista cliente.
end