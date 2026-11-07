# frozen_string_literal: true

# Fecha en que se reembolsó un pago, para ubicar el reembolso en el mes en que
# ocurrió (estado de resultados / flujo mensual).
class AddRefundedAtToPayments < ActiveRecord::Migration[8.0]
  def up
    add_column :payments, :refunded_at, :date
    add_index :payments, :refunded_at

    tz = connection.quote(Time.zone.tzinfo.name)
    execute <<~SQL.squish
      UPDATE payments
      SET refunded_at = (updated_at AT TIME ZONE 'UTC' AT TIME ZONE #{tz})::date
      WHERE status = 'Refunded' AND refunded_at IS NULL
    SQL
  end

  def down
    remove_index :payments, :refunded_at
    remove_column :payments, :refunded_at
  end
end
