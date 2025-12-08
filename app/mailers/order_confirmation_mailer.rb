# frozen_string_literal: true

class OrderConfirmationMailer < ApplicationMailer
  def order_confirmation(sale_order)
    @sale_order = sale_order
    @user = sale_order.user
    @items = sale_order.sale_order_items.includes(:product)
    @shipping_address = sale_order.order_shipping_address

    mail(
      to: @user.email,
      subject: "Confirmación de Pedido ##{@sale_order.id} - Pasatiempos"
    )
  end
end
