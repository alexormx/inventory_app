# frozen_string_literal: true

class PreorderMailer < ApplicationMailer
  default from: 'notificaciones@tienda.test'

  def assigned(preorder_reservation_id)
    @reservation = PreorderReservation.find(preorder_reservation_id)
    @product = @reservation.product
    mail to: @reservation.user.email, subject: "Tu preventa de #{@product.product_name} está lista para avanzar"
  end
end
