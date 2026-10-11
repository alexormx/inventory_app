# frozen_string_literal: true

module CartsHelper
  # Texto de la línea de envío del carrito: el checkout cobra según el método
  # elegido, así que aquí se muestra la tarifa activa más barata.
  def cart_shipping_label(cart)
    return '¡Gratis!' if cart.free_shipping_eligible?

    cheapest = Shipping::Calculator.cheapest_active_rate
    cheapest ? "desde #{number_to_currency(cheapest, precision: 0)}" : 'A calcular'
  end
end
