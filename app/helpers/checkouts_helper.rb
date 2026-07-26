# frozen_string_literal: true

module CheckoutsHelper
  # Costo de envío mostrado en el checkout. Usa el MISMO Shipping::Calculator que
  # cobra Checkout::CreateOrder, para que lo que ve el cliente coincida siempre
  # con lo que se cobra (no el base_cost configurado del método, que puede diferir).
  def checkout_shipping_cost(method_code, address: nil, cart: nil)
    return 0 if method_code.blank?

    Shipping::Calculator.quote(
      method_code: method_code,
      user: current_user,
      address: address,
      cart: cart
    )
  end
end
