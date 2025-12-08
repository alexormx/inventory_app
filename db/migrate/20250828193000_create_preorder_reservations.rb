# frozen_string_literal: true

class CreatePreorderReservations < ActiveRecord::Migration[8.0]
  def change
    create_table :preorder_reservations do |t|
      t.references :product, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      # Usamos string porque sale_orders.id es string (no integer)
      t.string :sale_order_id
      t.integer :quantity, null: false
      t.integer :status, null: false, default: 0 # 0=pending
      t.datetime :reserved_at, null: false
      t.datetime :assigned_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.text :notes
      t.timestamps
    end
    add_index :preorder_reservations, %i[product_id status reserved_at], name: 'idx_preorders_fifo'
    add_index :preorder_reservations, :sale_order_id
    add_foreign_key :preorder_reservations, :sale_orders, column: :sale_order_id
  end
end
