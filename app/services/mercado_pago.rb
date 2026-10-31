# frozen_string_literal: true

# Integración con Mercado Pago Checkout Pro.
#
# Credenciales (solo por ENV, nunca en código, logs ni salida):
#   MERCADOPAGO_ACCESS_TOKEN   - Access Token de la aplicación (prueba o producción)
#   MERCADOPAGO_WEBHOOK_SECRET - clave secreta para validar la firma de los webhooks
module MercadoPago
  API_BASE = 'https://api.mercadopago.com'
  PROVIDER_STATUSES_PENDING = %w[pending in_process authorized in_mediation].freeze
  PROVIDER_STATUSES_REFUNDED = %w[refunded charged_back].freeze

  class Error < StandardError; end

  def self.access_token
    ENV.fetch('MERCADOPAGO_ACCESS_TOKEN', nil).presence
  end

  def self.webhook_secret
    ENV.fetch('MERCADOPAGO_WEBHOOK_SECRET', nil).presence
  end

  def self.configured?
    access_token.present?
  end
end
