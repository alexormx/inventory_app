# frozen_string_literal: true

class AddInventoryLocationToInventories < ActiveRecord::Migration[8.0]
  def change
    add_reference :inventories, :inventory_location, null: true, foreign_key: true
    add_index :inventories, %i[inventory_location_id status]
  end
end
