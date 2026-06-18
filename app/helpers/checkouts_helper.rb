# frozen_string_literal: true

module CheckoutsHelper
  # Costo de envío mostrado en el checkout. Usa el MISMO Shipping::Calculator que
  # cobra Checkout::CreateOrder, para que lo que ve el cliente coincida siempre
  # con lo que se cobra (no el base_cost configurado del método, que puede diferir).
  def checkout_shipping_cost(method_code, address: nil, cart: nil)
    return 0 if method_code.blank?

    Shipping::Calculator.boot_defaults if Shipping::Calculator.respond_to?(:boot_defaults)
    calculator = Shipping::Calculator.resolve(method_code)
    return 0 unless calculator

    calculator.new.calculate(user: current_user, address: address, cart: cart)
  rescue StandardError => e
    Rails.logger.warn("[checkout_shipping_cost] #{e.class}: #{e.message}")
    0
  end
end
