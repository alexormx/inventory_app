# frozen_string_literal: true

module ShoppingCarts
  # Vencimiento del carrito de sesión de un visitante: 4 h después de su último
  # cambio (ShoppingCart::IDLE_TTL), igual que el carrito durable.
  module SessionCartExpiry
    TOUCH_KEY = 'cart_touched_at'
    # Marca de un solo uso: el carrito venció al iniciar sesión y la siguiente
    # página de la tienda debe avisarlo.
    NOTICE_KEY = 'cart_expired_notice'
    NOTICE = 'Tu carrito venció tras 4 horas sin actividad y liberamos las piezas apartadas.'

    module_function

    def touch!(session)
      session[TOUCH_KEY] = Time.current.to_i
    end

    # Un carrito sin marca (anterior a este cambio) nunca se considera vencido.
    def stale?(session)
      stamp = session[TOUCH_KEY]
      session[:cart].present? && stamp.present? && Time.zone.at(stamp.to_i) < ShoppingCart::IDLE_TTL.ago
    end

    def clear!(session, notify: false)
      session[:cart] = {}
      session.delete(TOUCH_KEY)
      session[NOTICE_KEY] = true if notify
    end

    # true una sola vez si quedó pendiente avisar un vencimiento.
    def take_notice!(session)
      session.delete(NOTICE_KEY).present?
    end

    # Marca un carrito con líneas que aún no tiene marca, para empezar a contar.
    def stamp_if_missing!(session)
      touch!(session) if session[:cart].present? && session[TOUCH_KEY].blank?
    end
  end
end
