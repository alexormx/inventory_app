# frozen_string_literal: true

class AddShippingCostToSaleOrdersAndShipments < ActiveRecord::Migration[8.0]
  def change
    add_column :sale_orders, :shipping_cost, :decimal, precision: 10, scale: 2, null: false, default: 0
    add_column :shipments, :shipping_cost, :decimal, precision: 10, scale: 2, null: false, default: 0
  end
end
