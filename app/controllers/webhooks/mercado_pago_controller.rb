# frozen_string_literal: true

module Webhooks
  # POST /webhooks/mercado_pago — avisos de Mercado Pago (notification_url).
  # ActionController::API: sin sesión, CSRF, visitas ni allow_browser.
  class MercadoPagoController < ActionController::API
    def create
      return head(:ok) unless payment_notification?

      data_id = params['data.id'].presence || params.dig(:data, :id).to_s
      unless MercadoPago::WebhookSignature.valid?(signature_header: request.headers['x-signature'],
                                                  request_id: request.headers['x-request-id'],
                                                  data_id: data_id)
        Rails.logger.warn('[Webhooks::MercadoPago] firma inválida')
        return head(:unauthorized)
      end

      MercadoPago::SyncPaymentJob.perform_later(data_id) if data_id.to_s.match?(/\A\d+\z/)
      head :ok
    end

    private

    # Solo los Webhooks de pagos (type=payment), que vienen firmados. Los
    # avisos IPN viejos (topic=payment, merchant_order...) no traen firma y
    # Mercado Pago los manda en paralelo: se aceptan con 200 sin procesar para
    # que no los reintente; el Webhook firmado del mismo pago basta.
    def payment_notification?
      params[:type].to_s == 'payment'
    end
  end
end
