# frozen_string_literal: true

class AddMissingFkIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :sale_order_items, :sale_order_id, name: 'index_sale_order_items_on_sale_order_id'
    add_index :purchase_order_items, :purchase_order_id, name: 'index_purchase_order_items_on_purchase_order_id'
    add_index :payments, :sale_order_id, name: 'index_payments_on_sale_order_id'
    add_index :shipments, :sale_order_id, name: 'index_shipments_on_sale_order_id'
  end
end
