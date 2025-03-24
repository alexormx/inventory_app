class AddDimensionsToProductsAndTotalsToPurchaseOrders < ActiveRecord::Migration[8.0]
  def up
    # Products table
    add_column :products, :weight_gr, :integer, null: false, default: 100
    add_column :products, :length_cm, :integer, null: false, default: 16
    add_column :products, :width_cm,  :integer, null: false, default: 4
    add_column :products, :height_cm, :integer, null: false, default: 4

    # Purchase Orders table
    add_column :purchase_orders, :total_volume, :decimal, precision: 10, scale: 2, null: false, default: 0.0
    add_column :purchase_orders, :total_weight, :decimal, precision: 10, scale: 2, null: false, default: 0.0
  end

  def down
    remove_column :products, :weight_gr
    remove_column :products, :length_cm
    remove_column :products, :width_cm
    remove_column :products, :height_cm

    remove_column :purchase_orders, :total_volume
    remove_column :purchase_orders, :total_weight
  end
end
