class ChangeSaleOrderIdTypeInOrderShippingAddresses < ActiveRecord::Migration[8.0]
  def change
    # En SQLite no soporta ALTER TYPE directo; recreamos columna de forma segura.
    reversible do |dir|
      dir.up do
        # Renombrar la vieja columna
        rename_column :order_shipping_addresses, :sale_order_id, :sale_order_id_int
        # Agregar nueva columna string
        add_column :order_shipping_addresses, :sale_order_id, :string
        # Copiar datos convertidos a string
        execute <<~SQL
          UPDATE order_shipping_addresses SET sale_order_id = CAST(sale_order_id_int AS TEXT)
        SQL
        # Quitar índice único viejo si existe y recrear sobre nueva
        remove_index :order_shipping_addresses, name: :index_order_shipping_addresses_on_sale_order_id rescue nil
        add_index :order_shipping_addresses, :sale_order_id, unique: true
        # Eliminar columna vieja
        remove_column :order_shipping_addresses, :sale_order_id_int
        # Agregar FK (no nativa en SQLite, pero en Postgres sí operará en deploy)
        add_foreign_key :order_shipping_addresses, :sale_orders, column: :sale_order_id
      end
      dir.down do
        # Reversión (simplificada): intentar volver a integer
        add_column :order_shipping_addresses, :sale_order_id_int, :integer
        execute <<~SQL
          UPDATE order_shipping_addresses SET sale_order_id_int = CAST(sale_order_id AS INTEGER)
        SQL
        remove_index :order_shipping_addresses, :sale_order_id rescue nil
        remove_column :order_shipping_addresses, :sale_order_id
        rename_column :order_shipping_addresses, :sale_order_id_int, :sale_order_id
        add_index :order_shipping_addresses, :sale_order_id, unique: true
      end
    end
  end
end
