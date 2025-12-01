# frozen_string_literal: true

class CreateInventoryAdjustments < ActiveRecord::Migration[8.0]
  def change
    create_table :inventory_adjustments do |t|
      t.string  :code
      t.string  :status, null: false, default: 'draft'
      t.string  :adjustment_type, null: false, default: 'audit'
      t.datetime :found_at
      t.string  :reference
      t.text    :note
      t.integer :user_id
      t.timestamps
    end

    add_index :inventory_adjustments, :code, unique: true
    add_index :inventory_adjustments, :found_at
    add_index :inventory_adjustments, :adjustment_type

    create_table :inventory_adjustment_lines do |t|
      t.integer :inventory_adjustment_id, null: false
      t.integer :product_id, null: false
      t.integer :quantity, null: false
      t.string  :reason
      t.decimal :unit_cost, precision: 10, scale: 2
      t.text    :note
      t.timestamps
    end

    add_index :inventory_adjustment_lines, :inventory_adjustment_id
    add_index :inventory_adjustment_lines, :product_id

    create_table :inventory_adjustment_entries do |t|
      t.integer :inventory_adjustment_line_id, null: false
      t.integer :inventory_id, null: false
      t.string  :action, null: false
      t.timestamps
    end

    add_index :inventory_adjustment_entries, :inventory_adjustment_line_id, name: :idx_adj_entries_line
    add_index :inventory_adjustment_entries, :inventory_id
  end
end
