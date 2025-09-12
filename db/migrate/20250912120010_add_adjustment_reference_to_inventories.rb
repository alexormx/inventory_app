class AddAdjustmentReferenceToInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :inventories, :adjustment_reference, :string
    add_index :inventories, :adjustment_reference
  end
end
