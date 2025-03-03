class CreateSaleOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :sale_orders, id: false do |t|  # Disable default 'id' column
      t.string :id, primary_key: true  # Define custom primary key
      t.references :user, null: false, foreign_key: true
      t.date :order_date, null: false
      t.references :payment, foreign_key: true, null: false
      t.references :shipment, foreign_key: true, null: false
      t.decimal :subtotal, precision: 10, scale: 2, null: false
      t.decimal :tax_rate, precision: 5, scale: 2, null: false
      t.decimal :total_tax, precision: 10, scale: 2, null: false
      t.decimal :total_order_value, precision: 10, scale: 2, null: false
      t.decimal :discount, precision: 10, scale: 2
      t.string :status, null: false
      t.text :notes

      t.timestamps
    end
  end
end
