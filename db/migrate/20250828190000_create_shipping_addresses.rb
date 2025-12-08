# frozen_string_literal: true

class CreateShippingAddresses < ActiveRecord::Migration[8.0]
  def change
    create_table :shipping_addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :label, null: false, default: 'Principal'
      t.string :full_name, null: false
      t.string :line1, null: false
      t.string :line2
      t.string :city, null: false
      t.string :state
      t.string :postal_code, null: false
      t.string :country, null: false, default: 'MX'
      t.boolean :default, null: false, default: false
      t.timestamps
    end
    add_index :shipping_addresses, %i[user_id default]
  end
end
