class AddSaleOrderItemIdToInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :inventories, :sale_order_item_id, :integer
    add_index  :inventories, :sale_order_item_id
  end
end
