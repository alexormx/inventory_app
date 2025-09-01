class AddLocationFieldsToShippingAddresses < ActiveRecord::Migration[7.1]
  def change
    add_column :shipping_addresses, :settlement, :string
    add_column :shipping_addresses, :municipality, :string
    # state ya existe; asegurar no nulo a futuro (por ahora permitir nil para migración suave)
    add_index :shipping_addresses, :postal_code
  end
end
