# frozen_string_literal: true

module MercadoPago
  # Crea la preferencia de Checkout Pro para el pago pendiente de un pedido y
  # devuelve la URL de Mercado Pago a la que se redirige al cliente.
  #
  # Se cobra el total del pedido como una sola línea: así lo que paga el
  # cliente coincide exacto con payments.amount (envío, descuentos e impuestos
  # ya incluidos) y SyncPayment puede compararlo sin redondeos por partida.
  class CreatePreference
    Result = Struct.new(:redirect_url, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    # urls: { success:, pending:, failure:, notification: }
    def initialize(sale_order:, urls:, client: nil)
      @sale_order = sale_order
      @urls = urls
      @client = client
    end

    def call
      return Result.new(error: 'Este pedido está cancelado y ya no se puede pagar.') if @sale_order.status.in?(SaleOrder::NO_DEBT_STATUSES)

      payment = @sale_order.payments.mercado_pago.find_by(status: 'Pending')
      return Result.new(error: 'Este pedido no tiene un pago pendiente con Mercado Pago.') unless payment

      response = client.create_preference(body(payment), idempotency_key: "preference-#{payment.id}-#{SecureRandom.uuid}")
      payment.update!(provider_preference_id: response['id'])
      Result.new(redirect_url: response['init_point'])
    rescue MercadoPago::Error => e
      Rails.logger.error("[MercadoPago::CreatePreference] order=#{@sale_order.id} #{e.message}")
      Result.new(error: 'No pudimos abrir Mercado Pago. Intenta de nuevo en unos minutos.')
    end

    private

    def client
      @client ||= MercadoPago::Client.new
    end

    def body(payment)
      user = @sale_order.user
      {
        items: [{
          id: @sale_order.id.to_s,
          title: "Pedido #{@sale_order.id} - Pasatiempos a Escala",
          quantity: 1,
          currency_id: 'MXN',
          unit_price: payment.amount.to_d.round(2).to_f
        }],
        # En modo prueba no se manda el correo real: Mercado Pago rechaza el
        # pago si una de las partes es real y la otra de prueba.
        payer: (MercadoPago.test_mode? ? nil : { email: user.email, name: user.name.to_s }.compact_blank),
        external_reference: @sale_order.id.to_s,
        metadata: { sale_order_id: @sale_order.id, payment_id: payment.id },
        back_urls: @urls.slice(:success, :pending, :failure),
        auto_return: 'approved',
        notification_url: @urls[:notification],
        statement_descriptor: 'PASATIEMPOS'
      }.compact
    end
  end
end
