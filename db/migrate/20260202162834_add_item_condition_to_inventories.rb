# frozen_string_literal: true

class AddItemConditionToInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :inventories, :item_condition, :integer, default: 0, null: false
    add_index :inventories, :item_condition
  end
end
