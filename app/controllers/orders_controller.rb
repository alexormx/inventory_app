# frozen_string_literal: true

class OrdersController < ApplicationController
  before_action :authenticate_user!

  def index
    @orders = current_user.sale_orders.order(created_at: :desc)
  end

  def show
    @order = find_order
  end

  def summary
    @order = find_order
    # Override layout only when admin explicitly requests admin context
    if current_user&.admin? && params[:admin_context] == '1'
      render :summary, layout: 'admin'
    else
      render :summary, layout: 'customer'
    end
  end

  private

  def find_order
    # Si es admin puede ver cualquier orden; si no, sólo las propias
    if current_user.role == 'admin'
      SaleOrder.find(params[:id])
    else
      current_user.sale_orders.find(params[:id])
    end
  end
end