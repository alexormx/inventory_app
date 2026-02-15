# frozen_string_literal: true

class AddDirectionToInventoryAdjustmentLines < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:inventory_adjustment_lines)

    add_column :inventory_adjustment_lines, :direction, :string, null: false, default: 'increase' unless column_exists?(:inventory_adjustment_lines, :direction)

    return if index_exists?(:inventory_adjustment_lines, :direction)

    add_index :inventory_adjustment_lines, :direction

  end

  def down
    return unless table_exists?(:inventory_adjustment_lines)

    remove_index :inventory_adjustment_lines, :direction if index_exists?(:inventory_adjustment_lines, :direction)
    return unless column_exists?(:inventory_adjustment_lines, :direction)

    remove_column :inventory_adjustment_lines, :direction

  end
end
