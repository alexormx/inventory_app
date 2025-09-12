class AddSourceToInventoriesAndKindToPurchaseOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :inventories, :source, :string
    add_index  :inventories, :source

    add_column :purchase_orders, :kind, :string, null: false, default: "regular"
    add_index  :purchase_orders, :kind
  end
end
