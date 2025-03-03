class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :payment_method, null: false
      t.string :status, null: false, default: "Pending"
      t.date :paid_at

      t.timestamps
    end
  end
end
