# frozen_string_literal: true

namespace :mercado_pago do
  # Vuelve a consultar un pago en la API de Mercado Pago y lo refleja en el
  # pedido (mismo camino que el webhook). Sirve para corregir un pago que no
  # se sincronizó, p. ej. un cobro de prueba que quedó registrado como real.
  #   heroku run rake 'mercado_pago:resync[187156758940]'
  desc 'Re-sincroniza un pago de Mercado Pago por su payment id'
  task :resync, [:payment_id] => :environment do |_t, args|
    abort 'Uso: rake mercado_pago:resync[PAYMENT_ID]' if args[:payment_id].blank?

    result = MercadoPago::SyncPayment.call(provider_payment_id: args[:payment_id])
    if result.ignored_reason
      puts "Ignorado: #{result.ignored_reason}"
    else
      order = result.payment.sale_order.reload
      puts "Pedido #{order.id}: estado=#{order.status} pago=#{result.payment.status} " \
           "mercado_pago=#{result.provider_status} prueba=#{result.test_payment?}"
    end
  end
end
