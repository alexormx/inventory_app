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

  PaymentBrand = Struct.new(:key, :icon, :tagline, keyword_init: true)

  # Identidad visual de cada método de pago en el checkout (colores en
  # custom.scss, .pm-option--<key>). Se reconoce por código, nombre o banco
  # para no depender de cómo se dio de alta cada método en el admin.
  def payment_method_brand(payment_method)
    text = [payment_method.code, payment_method.name, payment_method.bank_name].compact.join(' ').downcase
    if payment_method.code == 'mercado_pago' || text.match?(/mercado\s*pago/)
      PaymentBrand.new(key: 'mercado-pago', icon: 'fa-solid fa-handshake', tagline: 'Tarjeta, OXXO o saldo Mercado Pago')
    elsif text.match?(/spin|oxxo/)
      PaymentBrand.new(key: 'spin', icon: 'fa-solid fa-store', tagline: 'Efectivo en tienda OXXO o transferencia')
    elsif text.include?('bbva')
      PaymentBrand.new(key: 'bbva', icon: 'fa-solid fa-building-columns', tagline: 'Transferencia SPEI o depósito')
    else
      PaymentBrand.new(key: 'default', icon: 'fa-solid fa-wallet', tagline: nil)
    end
  end
end
