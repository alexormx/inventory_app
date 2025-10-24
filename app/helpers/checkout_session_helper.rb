# frozen_string_literal: true

module CheckoutSessionHelper
  # Claves de sesión normalizadas como strings (Rails guarda la sesión con strings)
  SESSION_KEYS = {
    cart: 'cart',
    checkout_token: 'checkout_token',
    checkout_notes: 'checkout_notes',
    shipping_info: 'shipping_info'
  }.freeze

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

  # Obtener notas de checkout
  def checkout_notes
    session[SESSION_KEYS[:checkout_notes]]
  end

  # Establecer notas de checkout
  def set_checkout_notes(notes)
    session[SESSION_KEYS[:checkout_notes]] = notes
  end

  # Limpiar toda la sesión de checkout
  def clear_checkout_session!
    session[SESSION_KEYS[:cart]] = {}
    session[SESSION_KEYS[:checkout_token]] = nil
    session.delete(SESSION_KEYS[:checkout_notes])
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
