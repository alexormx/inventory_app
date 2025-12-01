# frozen_string_literal: true

class AddShippingCostToPurchaseOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :purchase_orders, :shipping_cost, :decimal, precision: 10, scale: 2, null: false, default: 0.0
    add_column :purchase_orders, :tax_cost, :decimal, precision: 10, scale: 2, null: false, default: 0.0
    add_column :purchase_orders, :other_cost, :decimal, precision: 10, scale: 2, null: false, default: 0.0
  end
end
