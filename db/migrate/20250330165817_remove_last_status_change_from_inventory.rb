class RemoveLastStatusChangeFromInventory < ActiveRecord::Migration[8.0]
  def up
    remove_column :inventories, :last_status_change
  end

  def down
    add_column :inventories, :last_status_change, :datetime
  end
end
