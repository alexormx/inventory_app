# frozen_string_literal: true

class AddStatusChangedAtToInventory < ActiveRecord::Migration[8.0]
  def up
    add_column :inventories, :status_changed_at, :datetime, default: -> { 'CURRENT_TIMESTAMP' }, null: false
    add_column :inventories, :purchase_order_item_id, :integer
  end

  def down
    remove_column :inventories, :purchase_order_item_id
    remove_column :inventories, :status_changed_at
  end
end
