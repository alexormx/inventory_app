# frozen_string_literal: true

class OrderConfirmationMailer < ApplicationMailer
  def order_confirmation(sale_order)
    @sale_order = sale_order
    @user = sale_order.user
    @items = sale_order.sale_order_items.includes(:product)
    @shipping_address = sale_order.order_shipping_address
    @payment = sale_order.payments.order(:created_at, :id).last
    # Datos vigentes del método (CLABE, banco, instrucciones) para que el
    # correo diga cómo pagar; antes solo remitía a "lo que viste en el checkout".
    @payment_method_record = PaymentMethod.find_by(code: @payment&.payment_method)

    mail(
      to: @user.email,
      subject: "Confirmación de Pedido ##{@sale_order.id} - Pasatiempos"
    )
  end

  # Ficha de OXXO/SPEI de Mercado Pago, en cuanto Mercado Pago la genera.
  def mercado_pago_ticket(sale_order)
    @sale_order = sale_order
    @user = sale_order.user
    @payment = sale_order.payments.mercado_pago.where.not(provider_ticket_url: nil).order(:created_at).last
    return if @payment.nil?

    mail(
      to: @user.email,
      subject: "Ficha de pago de tu pedido ##{@sale_order.id} - Pasatiempos"
    )
  end

  def payment_confirmation(sale_order)
    @sale_order = sale_order
    @user = sale_order.user

    mail(
      to: @user.email,
      subject: "Recibimos tu pago - Pedido ##{@sale_order.id} - Pasatiempos"
    )
  end
end
