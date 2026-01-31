class CreatePaymentMethods < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_methods do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.text :description
      t.text :instructions
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0

      t.timestamps
    end
    add_index :payment_methods, :code, unique: true
    add_index :payment_methods, :active
    add_index :payment_methods, :position
  end
end
