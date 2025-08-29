class CreatePreorderReservations < ActiveRecord::Migration[7.1]
  def change
    create_table :preorder_reservations do |t|
      t.references :product, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      # sale_orders usa id :string, especificamos type: :string para evitar mismatch bigint vs varchar
      t.references :sale_order, type: :string, foreign_key: true
      t.integer :quantity, null: false
      t.integer :status, null: false, default: 0 # 0=pending
      t.datetime :reserved_at, null: false
      t.datetime :assigned_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.text :notes
      t.timestamps
    end
    add_index :preorder_reservations, [:product_id, :status, :reserved_at], name: "idx_preorders_fifo"
  end
end
