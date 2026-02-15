# frozen_string_literal: true

class AddApplyReverseColumnsToInventoryAdjustments < ActiveRecord::Migration[8.0]
  def change
    # Idempotente: sólo agregar si no existen (SQLite produce error de duplicate otherwise)
    unless column_exists?(:inventory_adjustments, :applied_at)
      add_column :inventory_adjustments, :applied_at, :datetime
      add_index :inventory_adjustments, :applied_at unless index_exists?(:inventory_adjustments, :applied_at)
    end

    unless column_exists?(:inventory_adjustments, :reversed_at)
      add_column :inventory_adjustments, :reversed_at, :datetime
      add_index :inventory_adjustments, :reversed_at unless index_exists?(:inventory_adjustments, :reversed_at)
    end

    unless column_exists?(:inventory_adjustments, :applied_by_id)
      add_column :inventory_adjustments, :applied_by_id, :bigint
      add_index :inventory_adjustments, :applied_by_id unless index_exists?(:inventory_adjustments, :applied_by_id)
      add_foreign_key :inventory_adjustments, :users, column: :applied_by_id unless foreign_key_exists?(:inventory_adjustments, :users, column: :applied_by_id)
    end

    return if column_exists?(:inventory_adjustments, :reversed_by_id)

    add_column :inventory_adjustments, :reversed_by_id, :bigint
    add_index :inventory_adjustments, :reversed_by_id unless index_exists?(:inventory_adjustments, :reversed_by_id)
    add_foreign_key :inventory_adjustments, :users, column: :reversed_by_id unless foreign_key_exists?(:inventory_adjustments, :users,
                                                                                                       column: :reversed_by_id)

  end
end
