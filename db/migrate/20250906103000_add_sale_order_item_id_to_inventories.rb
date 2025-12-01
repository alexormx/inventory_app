# frozen_string_literal: true

class AddSaleOrderItemIdToInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :inventories, :sale_order_item_id, :integer unless column_exists?(:inventories, :sale_order_item_id)

    return if index_exists?(:inventories, :sale_order_item_id)

    add_index :inventories, :sale_order_item_id
    
  end
end
