# frozen_string_literal: true

# Enlace a la ficha de pago (OXXO/SPEI) que genera Mercado Pago, para que el
# cliente la pueda volver a abrir desde su pedido.
class AddProviderTicketUrlToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :payments, :provider_ticket_url, :string
  end
end
