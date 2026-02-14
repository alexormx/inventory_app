# frozen_string_literal: true

class AddMissingIndexAndRemoveCodeFromInventoryAdjustments < ActiveRecord::Migration[8.0]
  def change
    # Add missing index on purchase_order_item_id for inventories
    add_index :inventories, :purchase_order_item_id, name: "index_inventories_on_purchase_order_item_id"

    # Remove unused 'code' column from inventory_adjustments
    remove_index :inventory_adjustments, :code, name: "index_inventory_adjustments_on_code", if_exists: true
    remove_column :inventory_adjustments, :code, :string
  end
end
