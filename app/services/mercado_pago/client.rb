# frozen_string_literal: true

require 'net/http'

module MercadoPago
  # Cliente HTTP mínimo (Net::HTTP) para las dos llamadas que usa Checkout Pro.
  # Sin gema: el dyno es de 512 MB y solo se necesitan dos endpoints.
  class Client
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    def initialize(access_token: MercadoPago.access_token)
      raise Error, 'Mercado Pago no está configurado' if access_token.blank?

      @access_token = access_token
    end

    # POST /checkout/preferences -> { 'id' => ..., 'init_point' => ... }
    def create_preference(body, idempotency_key:)
      request(Net::HTTP::Post, '/checkout/preferences', body: body, idempotency_key: idempotency_key)
    end

    # GET /v1/payments/:id -> el pago tal como lo ve Mercado Pago
    def payment(id)
      raise Error, 'payment id inválido' unless id.to_s.match?(/\A\d+\z/)

      request(Net::HTTP::Get, "/v1/payments/#{id}")
    end

    private

    def request(klass, path, body: nil, idempotency_key: nil)
      uri = URI.join(API_BASE, path)
      req = klass.new(uri)
      req['Authorization'] = "Bearer #{@access_token}"
      req['Content-Type'] = 'application/json'
      req['X-Idempotency-Key'] = idempotency_key if idempotency_key
      req.body = body.to_json if body

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                     open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(req)
      end
      parsed = response.body.present? ? JSON.parse(response.body) : {}
      return parsed if response.is_a?(Net::HTTPSuccess)

      # Solo código y mensaje de la API: nunca encabezados (llevan el token).
      raise Error, "Mercado Pago respondió #{response.code}: #{parsed['message'] || parsed['error']}"
    rescue JSON::ParserError
      raise Error, "Respuesta inválida de Mercado Pago (#{response&.code})"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise Error, "No se pudo conectar con Mercado Pago (#{e.class})"
    end
  end
end
