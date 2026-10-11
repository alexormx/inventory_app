# frozen_string_literal: true

module Carts
  # Vence los carritos durables con líneas que llevan ShoppingCart::IDLE_TTL
  # sin cambios, para liberar sus piezas aunque el cliente no regrese. Nunca
  # toca órdenes de venta.
  class ExpireIdleCartsJob < ApplicationJob
    queue_as :default

    def perform
      count = 0
      ShoppingCart.where(status: 'active')
                  .where(last_activity_at: ...ShoppingCart::IDLE_TTL.ago)
                  .where(id: ShoppingCartItem.select(:shopping_cart_id))
                  .find_each { |cart| count += 1 if ShoppingCarts::ExpireCart.call(cart) }
      Rails.logger.info("[Carts::ExpireIdleCartsJob] expired=#{count}")
      count
    end
  end
end
