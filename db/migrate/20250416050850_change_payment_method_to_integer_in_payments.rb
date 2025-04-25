class ChangePaymentMethodToIntegerInPayments < ActiveRecord::Migration[8.0]
  def up
    # Primero: renombra la columna antigua para preservar datos si fuera necesario
    rename_column :payments, :payment_method, :payment_method_old

    # Segundo: agrega nueva columna como integer
    add_column :payments, :payment_method, :integer

    # Tercero: intenta mapear los valores antiguos (si fueran strings válidas)
    execute <<-SQL
      UPDATE payments
      SET payment_method = CASE payment_method_old
        WHEN 'tarjeta_de_credito' THEN 0
        WHEN 'efectivo' THEN 1
        WHEN 'transferencia_bancaria' THEN 2
        ELSE NULL
      END
    SQL

    # Cuarto: elimina la columna vieja
    remove_column :payments, :payment_method_old
  end

  def down
    # Agrega la columna antigua como string
    add_column :payments, :payment_method_old, :string

    # Mapea los valores del enum de vuelta a texto
    execute <<-SQL
      UPDATE payments
      SET payment_method_old = CASE payment_method
        WHEN 0 THEN 'tarjeta_de_credito'
        WHEN 1 THEN 'efectivo'
        WHEN 2 THEN 'transferencia_bancaria'
        ELSE NULL
      END
    SQL

    # Elimina la columna tipo integer
    remove_column :payments, :payment_method

    # Renombra de vuelta
    rename_column :payments, :payment_method_old, :payment_method
  end
end
