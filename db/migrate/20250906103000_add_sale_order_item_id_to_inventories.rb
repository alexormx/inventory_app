class AddSaleOrderItemIdToInventories < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:inventories, :sale_order_item_id)
      add_column :inventories, :sale_order_item_id, :integer
    end

    unless index_exists?(:inventories, :sale_order_item_id)
      add_index  :inventories, :sale_order_item_id
    end
  end
end
