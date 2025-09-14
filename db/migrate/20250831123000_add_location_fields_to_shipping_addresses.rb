# frozen_string_literal: true

class AddLocationFieldsToShippingAddresses < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:shipping_addresses)

    add_column :shipping_addresses, :settlement, :string unless column_exists?(:shipping_addresses, :settlement)
    add_column :shipping_addresses, :municipality, :string unless column_exists?(:shipping_addresses, :municipality)
  end

  def down
    # Only remove columns if they exist (safe rollback)
    remove_column :shipping_addresses, :settlement if column_exists?(:shipping_addresses, :settlement)
    remove_column :shipping_addresses, :municipality if column_exists?(:shipping_addresses, :municipality)
  end
end

