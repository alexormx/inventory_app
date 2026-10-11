# frozen_string_literal: true

module Admin
  module ShoppingCartsHelper
    CART_STATUS_LABELS = {
      'active' => %w[Activo bg-primary],
      'converted' => ['Convertido en orden', 'bg-success'],
      'expired' => %w[Vencido bg-secondary],
      'merged' => ['Fusionado', 'bg-light text-dark'],
      'cleared' => ['Vaciado', 'bg-light text-dark']
    }.freeze

    def cart_status_badge(status)
      label, css = CART_STATUS_LABELS.fetch(status.to_s, [status.to_s.humanize, 'bg-light text-dark'])
      tag.span(label, class: "badge #{css}")
    end

    def cart_customer(cart)
      return 'Invitado' unless cart.user

      safe_join([cart.user.name.presence || cart.user.email, tag.div(cart.user.email, class: 'small text-muted')])
    end

    # Para un carrito activo: cuánto falta para las 4 h sin cambios.
    def cart_expires_in(cart)
      remaining = cart.last_activity_at + ShoppingCart::IDLE_TTL - Time.current
      return 'vence en breve' unless remaining.positive?

      "vence en #{distance_of_time_in_words(Time.current, Time.current + remaining)}"
    end

    def cart_datetime(time)
      time ? l(time.in_time_zone, format: '%d/%m/%Y %H:%M') : '—'
    end
  end
end
