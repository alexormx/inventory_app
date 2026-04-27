# frozen_string_literal: true

class CreateWhatsappRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :whatsapp_requests do |t|
      t.string :code, null: true
      t.integer :status, null: false, default: 0
      t.references :user, foreign_key: true, null: true
      t.string :session_token, null: true
      t.string :customer_name
      t.string :customer_phone
      t.string :customer_email
      t.text :customer_notes
      t.decimal :total_estimate, precision: 12, scale: 2, default: 0
      t.datetime :sent_at
      t.datetime :contacted_at
      t.datetime :converted_at
      t.string :sale_order_id, null: true
      t.foreign_key :sale_orders, column: :sale_order_id

      t.timestamps
    end

    add_index :whatsapp_requests, :code, unique: true
    add_index :whatsapp_requests, :session_token
    add_index :whatsapp_requests, :status
    add_index :whatsapp_requests, [:user_id, :status]

    create_table :whatsapp_request_items do |t|
      t.references :whatsapp_request, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_price_snapshot, precision: 12, scale: 2
      t.text :item_notes

      t.timestamps
    end

    add_index :whatsapp_request_items, [:whatsapp_request_id, :product_id], unique: true, name: 'idx_wa_request_items_unique'

    add_column :sale_orders, :origin, :string
    add_column :sale_orders, :whatsapp_request_id, :bigint
    add_index :sale_orders, :whatsapp_request_id
    add_index :sale_orders, :origin
    add_index :whatsapp_requests, :sale_order_id, name: 'idx_whatsapp_requests_sale_order'
  end
end
