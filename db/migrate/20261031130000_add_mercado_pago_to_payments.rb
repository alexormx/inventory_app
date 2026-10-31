# frozen_string_literal: true

# Mercado Pago Checkout Pro: datos del proveedor en cada pago y el método de
# pago en el catálogo, INACTIVO hasta que el admin lo active con credenciales.
class AddMercadoPagoToPayments < ActiveRecord::Migration[8.0]
  def up
    change_table :payments, bulk: true do |t|
      t.string :provider_preference_id
      t.string :provider_payment_id
      t.string :provider_status
      t.string :provider_status_detail
      t.string :provider_payment_type
    end
    add_index :payments, :provider_payment_id, unique: true, where: 'provider_payment_id IS NOT NULL'

    execute <<~SQL.squish
      INSERT INTO payment_methods (name, code, description, active, position, created_at, updated_at)
      SELECT 'Mercado Pago', 'mercado_pago',
             'Tarjeta de crédito o débito, meses sin intereses, OXXO o SPEI a través de Mercado Pago.',
             FALSE, 0, NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM payment_methods WHERE code = 'mercado_pago')
    SQL
  end

  def down
    remove_index :payments, :provider_payment_id
    change_table :payments, bulk: true do |t|
      t.remove :provider_preference_id, :provider_payment_id, :provider_status,
               :provider_status_detail, :provider_payment_type
    end
    execute "DELETE FROM payment_methods WHERE code = 'mercado_pago'"
  end
end
