# frozen_string_literal: true

class CreateInventoryEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :inventory_events do |t|
      t.bigint  :inventory_id, null: false
      t.integer :product_id, null: false
      t.string  :event_type, null: false
      t.decimal :previous_purchase_cost, precision: 10, scale: 2
      t.decimal :new_purchase_cost, precision: 10, scale: 2
      t.decimal :previous_sold_price, precision: 10, scale: 2
      t.decimal :new_sold_price, precision: 10, scale: 2
      t.string  :previous_sale_order_id
      t.string  :new_sale_order_id
      # Usamos :json para compatibilidad con SQLite en desarrollo; en Postgres se mapeará adecuadamente.
      t.json :metadata, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index :inventory_events, :inventory_id
    add_index :inventory_events, :product_id
    add_index :inventory_events, :event_type
    add_index :inventory_events, :created_at
    add_foreign_key :inventory_events, :inventories
    add_foreign_key :inventory_events, :products
  end
end
