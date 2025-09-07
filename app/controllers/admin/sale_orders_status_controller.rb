class Admin::SaleOrdersStatusController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def force_pending
    so = SaleOrder.find(params[:id])
    prev = so.status
    if so.update(status: "Pending")
      redirect_to admin_sale_order_path(so), notice: "SO pasada a Pending temporalmente (antes: #{prev}). Puedes editar y luego confirmar/entregar."
    else
      redirect_to admin_sale_order_path(so), alert: so.errors.full_messages.to_sentence
    end
  end

  def force_delivered
    so = SaleOrder.find(params[:id])
    prev = so.status
    if so.update(status: "Delivered")
      redirect_to admin_sale_order_path(so), notice: "SO marcada como Delivered (antes: #{prev})."
    else
      redirect_to admin_sale_order_path(so), alert: so.errors.full_messages.to_sentence
    end
  end
end
