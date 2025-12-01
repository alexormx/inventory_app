# frozen_string_literal: true

class AddPurchaseTrackingToProducts < ActiveRecord::Migration[8.0]
  def up
    # Remove old supplier reference
    remove_reference :products, :supplier, index: true, foreign_key: { to_table: :users }

    # Add new supplier tracking references
    add_reference :products, :preferred_supplier, foreign_key: { to_table: :users }
    add_reference :products, :last_supplier, foreign_key: { to_table: :users }

    # Purchase tracking
    add_column :products, :total_purchase_quantity, :integer, default: 0, null: false
    add_column :products, :total_purchase_value, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :products, :average_purchase_cost, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :products, :last_purchase_cost, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :products, :last_purchase_date, :date

    # Sales tracking
    add_column :products, :total_sales_quantity, :integer, default: 0, null: false
    add_column :products, :average_sales_price, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :products, :last_sales_price, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :products, :last_sales_date, :date
    add_column :products, :total_sales_value, :decimal, precision: 10, scale: 2, default: 0.0, null: false

    # Extra insights
    add_column :products, :total_purchase_order, :integer, default: 0, null: false
    add_column :products, :total_sales_order, :integer, default: 0, null: false
    add_column :products, :total_units_sold, :integer, default: 0, null: false

    # Add Financial Metrics Tracking
    add_column :products, :current_profit, :decimal, precision: 15, scale: 2, default: 0.0, null: false
    add_column :products, :current_inventory_value, :decimal, precision: 15, scale: 2, default: 0.0, null: false
    add_column :products, :projected_sales_value, :decimal, precision: 15, scale: 2, default: 0.0, null: false
    add_column :products, :projected_profit, :decimal, precision: 15, scale: 2, default: 0.0, null: false
  end

  def down
    # Remove Financial Metrics Tracking
    remove_column :products, :projected_profit
    remove_column :products, :projected_sales_value
    remove_column :products, :current_inventory_value
    remove_column :products, :current_profit

    # Reverse extra insights
    remove_column :products, :total_units_sold
    remove_column :products, :total_sales_order
    remove_column :products, :total_purchase_order

    # Reverse sales tracking
    remove_column :products, :total_sales_value
    remove_column :products, :last_sales_date
    remove_column :products, :last_sales_price
    remove_column :products, :average_sales_price
    remove_column :products, :total_sales_quantity

    # Reverse purchase tracking
    remove_column :products, :last_purchase_date
    remove_column :products, :last_purchase_cost
    remove_column :products, :average_purchase_cost
    remove_column :products, :total_purchase_value
    remove_column :products, :total_purchase_quantity

    # Remove new references
    remove_reference :products, :last_supplier, foreign_key: { to_table: :users }
    remove_reference :products, :preferred_supplier, foreign_key: { to_table: :users }

    # Restore old supplier reference
    add_reference :products, :supplier, foreign_key: { to_table: :users }
  end
end