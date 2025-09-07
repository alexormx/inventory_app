class AddPendingQuantitiesToSaleOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :sale_order_items, :preorder_quantity, :integer, null: false, default: 0
    add_column :sale_order_items, :backordered_quantity, :integer, null: false, default: 0
    add_index  :sale_order_items, :preorder_quantity
    add_index  :sale_order_items, :backordered_quantity
  end
end
