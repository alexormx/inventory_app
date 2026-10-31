# frozen_string_literal: true

module MercadoPago
  # El webhook responde 200 de inmediato y sincroniza aquí, en el worker. Si
  # la API de Mercado Pago falla, se reintenta; Mercado Pago además reenvía el
  # aviso si no recibe 200.
  class SyncPaymentJob < ApplicationJob
    queue_as :default
    retry_on MercadoPago::Error, wait: :polynomially_longer, attempts: 5

    def perform(provider_payment_id)
      MercadoPago::SyncPayment.call(provider_payment_id: provider_payment_id)
    end
  end
end
