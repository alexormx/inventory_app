# frozen_string_literal: true

class CreateOrderShippingAddresses < ActiveRecord::Migration[8.0]
  def change
    create_table :order_shipping_addresses do |t|
      # ID de sale_orders es string (custom). Definimos la columna explícitamente.
      t.string :sale_order_id, null: false
      t.bigint :source_shipping_address_id
      t.string :full_name, null: false
      t.string :line1, null: false
      t.string :line2
      t.string :city, null: false
      t.string :state
      t.string :postal_code, null: false
      t.string :country, null: false
      t.string :shipping_method, null: false
      # Usamos :json para compatibilidad local (SQLite) y producción (Postgres).
      # En Postgres podrías migrar luego a jsonb con una migración adicional si necesitas índices GIN.
      t.json :raw_address_json, null: false, default: {}
      t.timestamps
    end

    add_index :order_shipping_addresses, :sale_order_id, unique: true
    add_index :order_shipping_addresses, :source_shipping_address_id
    add_index :order_shipping_addresses, :shipping_method
    add_foreign_key :order_shipping_addresses, :sale_orders, column: :sale_order_id
  end
end
