class CreateShipments < ActiveRecord::Migration[8.0]
  def change
    create_table :shipments do |t|
      t.string :order_id, null: false  # Can be a sale order or purchase order
      t.string :tracking_number, null: false
      t.string :carrier, null: false
      t.string :status, null: false, default: "Pending"
      t.date :estimated_delivery, null: false
      t.date :actual_delivery
      t.timestamp :last_update, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.timestamps
    end
  end
end
