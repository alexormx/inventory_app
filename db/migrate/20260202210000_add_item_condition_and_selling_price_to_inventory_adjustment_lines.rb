# frozen_string_literal: true

class AddItemConditionAndSellingPriceToInventoryAdjustmentLines < ActiveRecord::Migration[8.0]
  def change
    add_column :inventory_adjustment_lines, :item_condition, :integer, default: 0, null: false
    add_column :inventory_adjustment_lines, :selling_price, :decimal, precision: 10, scale: 2
    add_index :inventory_adjustment_lines, :item_condition
  end
end
