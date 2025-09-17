class AdjustUserColumns < ActiveRecord::Migration[8.0]
  def up
    #remove unwanted column contact_name
    remove_column :users, :contact_name, :string

    # allow null values for name, phone and addres (making them optional)
    change_column :users, :name, :string, null: true
    change_column :users, :phone, :string, null: true
    change_column :users, :address, :string, null: true

    #Ensure discount_rate allows nil and has a default value (e.g., 0.0)
    change_column :users, :discount_rate, :decimal, precision: 5, scale: 2, null: true, default: 0.0
  end

  def down
    #add back the column contact_name
    add_column :users, :contact_name, :string

    # revert name, phone and address to NOT allow null values
    change_column :users, :name, :string, null: false
    change_column :users, :phone, :string, null: false
    change_column :users, :address, :string, null: false

    # Allow discount_rate to be nil and remove default value
    change_column :users, :discount_rate, :decimal, precision: 5, scale: 2, null: false, default: nil
  end
end

