class AddDiscontinuedToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :discontinued, :boolean, default: false, null: false
    add_index :products, :discontinued
  end
end
