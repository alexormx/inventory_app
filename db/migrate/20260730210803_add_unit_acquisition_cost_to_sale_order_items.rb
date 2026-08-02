# frozen_string_literal: true

# El COGS del dashboard se calculaba con products.average_purchase_cost, que
# Products::UpdateStatsService recalcula en cada compra. Eso reescribía los
# márgenes históricos: el margen de una venta de 2024 cambiaba al comprar ese
# producto en 2026. Congelamos el costo en la línea al momento de la venta.
class AddUnitAcquisitionCostToSaleOrderItems < ActiveRecord::Migration[8.0]
  def up
    add_column :sale_order_items, :unit_acquisition_cost, :decimal, precision: 10, scale: 2

    # Backfill en SQL puro: el dyno de producción es de 512MB y esta tabla crece
    # sin techo, así que no se puede materializar en memoria.
    execute <<~SQL.squish
      UPDATE sale_order_items
      SET unit_acquisition_cost = COALESCE(products.average_purchase_cost, 0)
      FROM products
      WHERE products.id = sale_order_items.product_id
        AND sale_order_items.unit_acquisition_cost IS NULL
    SQL

    add_index :sale_order_items, :unit_acquisition_cost
  end

  def down
    remove_index :sale_order_items, :unit_acquisition_cost
    remove_column :sale_order_items, :unit_acquisition_cost
  end
end
