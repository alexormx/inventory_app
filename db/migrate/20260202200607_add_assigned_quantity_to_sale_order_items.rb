# frozen_string_literal: true

class AddAssignedQuantityToSaleOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :sale_order_items, :assigned_quantity, :integer, default: 0, null: false
    add_index :sale_order_items, :assigned_quantity
  end
end
