class ChangeTrackingNumberNullableOnShipments < ActiveRecord::Migration[8.0]
  def change
    change_column_null :shipments, :tracking_number, true
  end
end
