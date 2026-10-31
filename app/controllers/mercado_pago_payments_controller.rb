# frozen_string_literal: true

# Pago de un pedido con Mercado Pago Checkout Pro.
#   POST /checkout/mercado_pago/:order_id/pay -> crea la preferencia y redirige
#   GET  /checkout/mercado_pago/return        -> regreso desde Mercado Pago
class MercadoPagoPaymentsController < ApplicationController
  include MercadoPagoRedirect

  before_action :authenticate_user!

  def pay
    order = current_user.sale_orders.find_by(id: params[:order_id])
    return redirect_to(root_path, alert: 'Pedido no encontrado.') unless order

    redirect_to_mercado_pago(order)
  end

  # Mercado Pago agrega payment_id, status y external_reference. El status de
  # la URL NO se usa para marcar el pago: se consulta la API (SyncPayment) y
  # el webhook confirma de todos modos si esta consulta falla.
  def back
    order = current_user.sale_orders.find_by(id: params[:external_reference].to_s)
    return redirect_to(orders_path, alert: 'No encontramos el pedido de este pago.') unless order

    provider_status = sync(params[:payment_id]) || params[:status].to_s
    redirect_to checkout_thank_you_path(order_id: order.id), **flash_for(provider_status)
  end

  private

  def sync(provider_payment_id)
    return if provider_payment_id.blank? || provider_payment_id == 'null'

    MercadoPago::SyncPayment.call(provider_payment_id: provider_payment_id).provider_status
  rescue MercadoPago::Error => e
    Rails.logger.error("[MercadoPagoPayments#return] #{e.message}")
    nil
  end

  def flash_for(provider_status)
    case provider_status
    when 'approved'
      { notice: '¡Pago recibido! Tu pedido quedó confirmado.' }
    when *MercadoPago::PROVIDER_STATUSES_PENDING
      { notice: 'Tu pago está en proceso. Te avisaremos en cuanto Mercado Pago lo confirme.' }
    else
      { alert: 'El pago no se completó. Puedes intentarlo de nuevo con otro medio de pago.' }
    end
  end
end
