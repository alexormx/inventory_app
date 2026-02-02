class CreateInventoryAssignmentLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :inventory_assignment_logs do |t|
      # sale_orders tiene id de tipo string
      t.string :sale_order_id, null: true
      t.references :sale_order_item, null: true, foreign_key: true
      t.references :product, null: true, foreign_key: true
      t.references :inventory, null: true, foreign_key: true
      t.datetime :assigned_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.integer :assignment_type, null: false, default: 0
      t.string :triggered_by, null: false, default: 'system'
      t.text :notes
      t.integer :quantity_assigned, default: 1
      t.integer :quantity_pending, default: 0
      t.timestamps
    end

    add_index :inventory_assignment_logs, :sale_order_id
    add_index :inventory_assignment_logs, :assigned_at
    add_index :inventory_assignment_logs, :assignment_type
    add_index :inventory_assignment_logs, :triggered_by
    add_foreign_key :inventory_assignment_logs, :sale_orders
  end
end
