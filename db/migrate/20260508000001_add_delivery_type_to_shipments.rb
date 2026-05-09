# frozen_string_literal: true

class AddDeliveryTypeToShipments < ActiveRecord::Migration[8.0]
  def change
    add_column :shipments, :delivery_type, :integer, default: 0, null: false
    add_index  :shipments, :delivery_type
  end
end
