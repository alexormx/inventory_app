# frozen_string_literal: true

# Crea la preferencia de Checkout Pro de un pedido y manda al cliente a
# Mercado Pago. Lo usan el checkout (al crear el pedido) y el botón "Pagar con
# Mercado Pago" del pedido (reintentos).
module MercadoPagoRedirect
  extend ActiveSupport::Concern

  private

  def redirect_to_mercado_pago(order)
    result = MercadoPago::CreatePreference.call(sale_order: order, urls: mercado_pago_urls)
    if result.success?
      redirect_to result.redirect_url, allow_other_host: true
    else
      redirect_to checkout_thank_you_path(order_id: order.id), alert: result.error
    end
  end

  def mercado_pago_urls
    back = mercado_pago_return_url
    { success: back, pending: back, failure: back, notification: webhooks_mercado_pago_url }
  end
end
