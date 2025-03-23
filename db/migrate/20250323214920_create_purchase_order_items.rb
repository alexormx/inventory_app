class CreatePurchaseOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :purchase_order_items do |t|
      t.string :purchase_order_id, null: false
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.decimal :unit_cost, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_foreign_key :purchase_order_items, :purchase_orders, column: :purchase_order_id
  end
end
