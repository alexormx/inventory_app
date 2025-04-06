class CreateSaleOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :sale_order_items do |t|
      t.string :sale_order_id, null: false
      t.references :product, null: false, foreign_key: true

      t.integer :quantity
      t.decimal :unit_cost, precision: 10, scale: 2, null: false
      t.decimal :unit_discount, precision: 10, scale: 2, default: 0.0
      t.decimal :unit_final_price, precision: 10, scale: 2
      t.decimal :total_line_cost, precision: 10, scale: 2
      t.decimal :total_line_volume, precision: 10, scale: 2
      t.decimal :total_line_weight, precision: 10, scale: 2

      t.timestamps
    end

    add_foreign_key :sale_order_items, :sale_orders, column: :sale_order_id
  end
end
