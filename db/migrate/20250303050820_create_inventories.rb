class CreateInventories < ActiveRecord::Migration[8.0]
  def change
    create_table :inventories do |t|
      t.references :product, null: false, foreign_key: true
      t.references :purchase_order, null: true, foreign_key: true, type: :string
      t.references :sale_order, null: true, foreign_key: true, type: :string
      t.decimal :purchase_cost, precision: 10, scale: 2, null: false
      t.decimal :sold_price, precision: 10, scale: 2
      t.string :status, null: false, default: "Available"
      t.timestamp :last_status_change, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.text :notes

      t.timestamps
    end
  end
end
