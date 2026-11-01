# frozen_string_literal: true

# Pedidos de la tienda que todavía no tienen envío: se les crea el envío
# pendiente con lo que eligió el cliente y el costo ya cobrado. insert_all
# salta los callbacks de Shipment, así que los totales no se tocan.
class BackfillShipmentsForStoreOrders < ActiveRecord::Migration[8.0]
  OPEN_STATUSES = %w[Pending Confirmed Preparing].freeze
  PICKUP_CODES = %w[recoger_tienda].freeze

  class MigrationShipment < ActiveRecord::Base
    self.table_name = 'shipments'
  end

  def up
    now = Time.current
    rows = select_rows(<<~SQL.squish)
      SELECT so.id, so.order_date, so.shipping_cost, osa.shipping_method, osa.raw_address_json::text
      FROM sale_orders so
      JOIN order_shipping_addresses osa ON osa.sale_order_id = so.id
      WHERE so.status IN (#{OPEN_STATUSES.map { |s| connection.quote(s) }.join(', ')})
        AND NOT EXISTS (SELECT 1 FROM shipments sh WHERE sh.sale_order_id = so.id)
    SQL
    return if rows.empty?

    shipments = rows.map do |id, order_date, cost, method, raw|
      name = method_name(raw).presence || method.to_s.humanize
      {
        sale_order_id: id,
        carrier: name.presence || 'Por asignar',
        estimated_delivery: (order_date.present? ? Date.parse(order_date.to_s) : now.to_date) + 7,
        shipping_cost: cost.to_d,
        status: 0,
        delivery_type: PICKUP_CODES.include?(method) ? 1 : 0,
        last_update: now, created_at: now, updated_at: now
      }
    end
    MigrationShipment.insert_all!(shipments)
    say "Envíos creados para #{shipments.size} pedido(s) de la tienda"
  end

  def method_name(raw)
    JSON.parse(raw.to_s).to_h['shipping_method_name']
  rescue JSON::ParserError
    nil
  end

  def down
    # Irreversible a propósito: no se distinguen de los envíos creados a mano.
  end
end
