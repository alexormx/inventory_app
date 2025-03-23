class AddTotalCostMxnToPurchaseOrders < ActiveRecord::Migration[8.0]
  def up
    add_column :purchase_orders, :total_cost, :decimal, precision: 10, scale: 2, null: false, default: 0.0
    add_column :purchase_orders, :total_cost_mxn, :decimal, precision: 10, scale: 2, null: false, default: 0.0
  end

  def down
    remove_column :purchase_orders, :total_cost
    remove_column :purchase_orders, :total_cost_mxn
  end
end
