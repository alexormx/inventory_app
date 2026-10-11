# frozen_string_literal: true

module CheckoutSessionHelper
  # Claves de sesión normalizadas como strings (Rails guarda la sesión con strings)
  SESSION_KEYS = {
    cart: 'cart',
    checkout_token: 'checkout_token',
    shipping_info: 'shipping_info'
  }.freeze

  # Tope de las notas del pedido (ver #set_checkout_notes).
  MAX_NOTES = 1000

  # Obtener información de envío normalizada
  def checkout_shipping_info
    raw = session[SESSION_KEYS[:shipping_info]] || {}
    {
      address_id: normalize_value(raw, 'address_id'),
      method: normalize_value(raw, 'method')
    }.compact
  end

  # Establecer información de envío
  def set_checkout_shipping_info(address_id:, method:)
    session[SESSION_KEYS[:shipping_info]] = {
      'address_id' => address_id,
      'method' => method
    }
  end

  # Obtener token de checkout
  def checkout_token
    session[SESSION_KEYS[:checkout_token]]
  end

  # Establecer token de checkout
  def set_checkout_token(token)
    session[SESSION_KEYS[:checkout_token]] = token
  end

  # Generar y guardar nuevo token de checkout
  def generate_checkout_token!
    token = SecureRandom.urlsafe_base64(32)
    set_checkout_token(token)
    token
  end

  # Las notas viven en el carrito durable, no en la cookie de sesión (4 KB):
  # unas notas largas rompían el checkout con CookieOverflow. El checkout
  # siempre exige sesión iniciada, así que el carrito durable existe.
  def checkout_notes
    storefront_cart.persistent_cart&.checkout_notes
  end

  def set_checkout_notes(notes)
    storefront_cart.persistent_cart&.update_column(:checkout_notes, notes.to_s.strip.first(MAX_NOTES).presence)
  end

  # Limpiar toda la sesión de checkout
  def clear_checkout_session!
    session[SESSION_KEYS[:cart]] = {}
    session[SESSION_KEYS[:checkout_token]] = nil
    session.delete(SESSION_KEYS[:shipping_info])
  end

  # Limpiar solo el token (para prevenir reuso)
  def clear_checkout_token!
    session[SESSION_KEYS[:checkout_token]] = nil
  end

  private

  # Normalizar valor de hash que puede tener claves string o symbol
  def normalize_value(hash, key)
    hash[key] || hash[key.to_sym]
  end
end
