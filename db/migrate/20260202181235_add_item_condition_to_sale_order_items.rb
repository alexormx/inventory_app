# frozen_string_literal: true

class AddItemConditionToSaleOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :sale_order_items, :item_condition, :integer, default: 0, null: false
    add_column :sale_order_items, :unit_selling_price, :decimal, precision: 10, scale: 2
    add_index :sale_order_items, :item_condition
  end
end
