class CreatePurchaseOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :purchase_orders, id: false do |t|  # Disable default 'id' column
      t.string :id, primary_key: true  # Define custom primary key
      t.references :user, null: false, foreign_key: true
      t.date :order_date, null: false
      t.date :expected_delivery_date, null: false
      t.date :actual_delivery_date
      t.decimal :subtotal, precision: 10, scale: 2, null: false
      t.decimal :total_order_cost, precision: 10, scale: 2, null: false
      t.string :status, null: false
      t.text :notes

      t.timestamps
    end
  end
end
