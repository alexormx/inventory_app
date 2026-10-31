# frozen_string_literal: true

module MercadoPago
  # Valida el encabezado x-signature de las notificaciones de Mercado Pago:
  #   x-signature: ts=<timestamp>,v1=<hmac sha256 hex>
  # sobre el manifiesto "id:<data.id>;request-id:<x-request-id>;ts:<ts>;"
  # con la clave secreta de webhooks de la aplicación.
  #
  # Aun con firma válida, SyncPayment vuelve a consultar el pago en la API:
  # la firma solo evita trabajo y ruido por avisos falsos.
  class WebhookSignature
    def self.valid?(...) = new(...).valid?

    def initialize(signature_header:, request_id:, data_id:, secret: MercadoPago.webhook_secret)
      @signature_header = signature_header.to_s
      @request_id = request_id.to_s
      @data_id = data_id.to_s
      @secret = secret
    end

    def valid?
      return false if @secret.blank?

      parts = @signature_header.split(',').to_h { |pair| pair.split('=', 2).map(&:strip) }
      ts = parts['ts']
      v1 = parts['v1']
      return false if ts.blank? || v1.blank?

      expected = OpenSSL::HMAC.hexdigest('SHA256', @secret, manifest(ts))
      ActiveSupport::SecurityUtils.secure_compare(expected, v1)
    end

    private

    def manifest(ts)
      data_id = @data_id.match?(/\A[[:alnum:]]+\z/) ? @data_id.downcase : @data_id
      out = +''
      out << "id:#{data_id};" if data_id.present?
      out << "request-id:#{@request_id};" if @request_id.present?
      out << "ts:#{ts};"
      out
    end
  end
end
