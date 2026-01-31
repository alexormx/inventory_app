class CreateShippingMethods < ActiveRecord::Migration[8.0]
  def change
    create_table :shipping_methods do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.text :description
      t.decimal :base_cost, precision: 10, scale: 2, default: 0
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0

      t.timestamps
    end
    add_index :shipping_methods, :code, unique: true
    add_index :shipping_methods, :active
    add_index :shipping_methods, :position
  end
end
