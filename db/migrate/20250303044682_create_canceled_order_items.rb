# frozen_string_literal: true

class CreateCanceledOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :canceled_order_items do |t|
      t.string :sale_order_id, null: false # ✅ Change from t.references to t.string
      t.references :product, null: false, foreign_key: true
      t.integer :canceled_quantity, null: false
      t.decimal :sale_price_at_cancellation, precision: 10, scale: 2, null: false
      t.text :cancellation_reason
      t.timestamp :canceled_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.timestamps
    end
    # ✅ Add the foreign key constraint manually
    add_foreign_key :canceled_order_items, :sale_orders, column: :sale_order_id, primary_key: :id
  end
end
