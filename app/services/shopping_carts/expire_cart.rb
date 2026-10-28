# frozen_string_literal: true

module ShoppingCarts
  # Vence un carrito durable que lleva ShoppingCart::IDLE_TTL sin cambios:
  # libera sus apartados y lo cierra como `expired`. Sus líneas se conservan
  # como historial; el siguiente "agregar" crea un carrito nuevo, y sus
  # productos pasan a los favoritos del cliente para que no se pierda lo que
  # le interesaba. Las órdenes de venta nunca se tocan aquí.
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
        save_lines_as_favorites(cart)
        expired = true
      end
      expired
    end

    def self.save_lines_as_favorites(cart)
      return if cart.user.nil?

      Product.where(id: cart.shopping_cart_items.select(:product_id)).find_each do |product|
        Favorite.save_for(cart.user, product, source: 'abandoned_cart')
      end
    end
    private_class_method :save_lines_as_favorites
  end
end
