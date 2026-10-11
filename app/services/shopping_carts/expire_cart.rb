# frozen_string_literal: true

module ShoppingCarts
  # Vence un carrito durable que lleva ShoppingCart::IDLE_TTL sin cambios:
  # libera sus apartados y lo cierra como `expired`. Sus líneas se conservan
  # como historial; el siguiente "agregar" crea un carrito nuevo. Las órdenes
  # de venta nunca se tocan aquí.
  class ExpireCart
    def self.stale?(cart)
      cart.status == 'active' &&
        cart.last_activity_at < ShoppingCart::IDLE_TTL.ago &&
        cart.shopping_cart_items.exists?
    end

    # true si lo venció. Se re-evalúa bajo el candado del carrito: una
    # mutación que llegó antes (otra pestaña) renovó la actividad y gana.
    def self.call(cart)
      expired = false
      ActiveRecord::Base.transaction do
        cart.lock!
        next unless stale?(cart)

        CartInventoryHold.for_cart(cart).delete_all
        cart.update!(status: 'expired', closed_at: Time.current, anonymous_token_digest: nil)
        expired = true
      end
      expired
    end
  end
end
