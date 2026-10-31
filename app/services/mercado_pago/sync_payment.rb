# frozen_string_literal: true

module MercadoPago
  # Trae un pago de la API de Mercado Pago y refleja su estado en el Payment
  # del pedido. Es la ÚNICA vía que marca un pago como cobrado: ni el regreso
  # del navegador ni el cuerpo del webhook se toman como verdad, solo la API.
  #
  # Idempotente: el webhook puede llegar varias veces y en desorden, y el
  # regreso del navegador puede correr al mismo tiempo; se serializa con un
  # candado sobre el Payment.
  class SyncPayment
    Result = Struct.new(:payment, :provider_status, :ignored_reason, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(provider_payment_id:, client: nil)
      @provider_payment_id = provider_payment_id.to_s
      @client = client
    end

    def call
      data = client.payment(@provider_payment_id)
      sale_order = SaleOrder.find_by(id: data['external_reference'].to_s)
      return ignored('pedido no encontrado', data) unless sale_order

      payment = sale_order.payments.mercado_pago.order(:created_at).last
      return ignored('el pedido no tiene pago de Mercado Pago', data) unless payment

      Payment.transaction do
        payment.lock!
        apply(payment, data)
      end
      Result.new(payment: payment, provider_status: data['status'])
    end

    private

    def client
      @client ||= MercadoPago::Client.new
    end

    def apply(payment, data)
      status = data['status'].to_s
      # Un intento rechazado posterior no debe tocar un pago ya cobrado con
      # otro intento; solo un reembolso/contracargo de ESE mismo cobro.
      if payment.status == 'Completed' && payment.provider_payment_id.present? &&
         payment.provider_payment_id != @provider_payment_id
        return
      end

      attrs = {
        provider_payment_id: @provider_payment_id,
        provider_status: status,
        provider_status_detail: data['status_detail'],
        provider_payment_type: data['payment_type_id']
      }

      case status
      when 'approved'
        if amount_matches?(payment, data)
          attrs[:status] = 'Completed'
        else
          Rails.logger.error("[MercadoPago::SyncPayment] monto distinto order=#{payment.sale_order_id} " \
                             "esperado=#{payment.amount} recibido=#{data['transaction_amount']} #{data['currency_id']}")
          attrs[:provider_status] = 'amount_mismatch'
        end
      when *MercadoPago::PROVIDER_STATUSES_REFUNDED
        attrs[:status] = 'Refunded' if payment.status == 'Completed'
      end
      # pending / in_process / rejected / cancelled: el Payment sigue Pending
      # para que el cliente pueda reintentar con otro medio desde su pedido.

      payment.update!(attrs)
    end

    def amount_matches?(payment, data)
      data['currency_id'] == 'MXN' &&
        data['transaction_amount'].to_d.round(2) >= payment.amount.to_d.round(2)
    end

    def ignored(reason, data)
      Rails.logger.warn("[MercadoPago::SyncPayment] ignorado mp_payment=#{@provider_payment_id} " \
                        "ref=#{data['external_reference']} (#{reason})")
      Result.new(provider_status: data['status'], ignored_reason: reason)
    end
  end
end
