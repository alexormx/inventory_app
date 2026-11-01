# frozen_string_literal: true

# live_mode del pago según la API de Mercado Pago: false = pago de prueba.
# Los pagos de prueba nunca se marcan cobrados y su pedido se cancela solo.
class AddProviderLiveModeToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :payments, :provider_live_mode, :boolean
  end
end
