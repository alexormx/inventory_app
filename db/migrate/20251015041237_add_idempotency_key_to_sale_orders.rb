# frozen_string_literal: true

class AddIdempotencyKeyToSaleOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :sale_orders, :idempotency_key, :string
    add_index :sale_orders, :idempotency_key
  end
end
