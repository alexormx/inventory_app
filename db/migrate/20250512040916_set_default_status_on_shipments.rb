# frozen_string_literal: true

class SetDefaultStatusOnShipments < ActiveRecord::Migration[8.0]
  def up
    # Rename the existing string column
    rename_column :shipments, :status, :status_old

    # Add new status column as integer
    add_column :shipments, :status, :integer

    # Map string values to integer enum values
    execute <<-SQL.squish
      UPDATE shipments
      SET status = CASE status_old
        WHEN 'pending' THEN 0
        WHEN 'shipped' THEN 1
        WHEN 'delivered' THEN 2
        WHEN 'canceled' THEN 3
        WHEN 'returned' THEN 4
        ELSE NULL
      END
    SQL

    # Remove old column
    remove_column :shipments, :status_old
  end

  def down
    # Add the old column back as string
    add_column :shipments, :status_old, :string

    # Convert back from integer to string
    execute <<-SQL.squish
      UPDATE shipments
      SET status_old = CASE status
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'shipped'
        WHEN 2 THEN 'delivered'
        WHEN 3 THEN 'canceled'
        WHEN 4 THEN 'returned'
        ELSE NULL
      END
    SQL

    # Remove the integer column and rename back
    remove_column :shipments, :status
    rename_column :shipments, :status_old, :status
  end
end
