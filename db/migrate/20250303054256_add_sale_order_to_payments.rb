# frozen_string_literal: true

class AddSaleOrderToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :payments, :sale_order_id, :string, null: false # ✅ Define as string
    add_column :shipments, :sale_order_id, :string, null: false # ✅ Define as string

    # ✅ Add the foreign key constraint manually
    add_foreign_key :payments, :sale_orders, column: :sale_order_id, primary_key: :id
    add_foreign_key :shipments, :sale_orders, column: :sale_order_id, primary_key: :id
  end
end
