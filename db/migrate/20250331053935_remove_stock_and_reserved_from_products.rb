class RemoveStockAndReservedFromProducts < ActiveRecord::Migration[8.0]
  def up
    remove_column :products, :stock_quantity, :integer
    remove_column :products, :reserved_quantity, :integer
  end

  def down
    add_column :products, :stock_quantity, :integer, default: 0
    add_column :products, :reserved_quantity, :integer, default: 0
  end
end
