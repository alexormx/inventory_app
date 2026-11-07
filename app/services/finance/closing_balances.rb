# frozen_string_literal: true

module Finance
  # Saldos al cierre de cada fecha pedida: anticipos por entregar e inventario
  # a costo reconstruido por pieza. Ver "Saldos al cierre" y "Reconstrucción
  # del inventario a costo" en el spec de finanzas mensual.
  #
  #   Finance::ClosingBalances.new(dates: [Date, ...]).call
  #   # => { Date => { advances: BigDecimal, inventory: BigDecimal } }
  class ClosingBalances
    # Estados que sacan una pieza del inventario en su status_changed_at.
    WRITE_OFF_STATUSES = %w[damaged lost scrap marketing].freeze
    # Vendidas sin orden ligada (datos antiguos): salen en su status_changed_at.
    ORPHAN_SOLD_STATUSES = %w[sold pre_sold].freeze

    # Filas (purchase_cost, entered_on date, exited_on date|null), una por
    # pieza; excluye piezas de órdenes de compra canceladas.
    def self.inventory_movements_sql
      write_off = Inventory.statuses.values_at(*WRITE_OFF_STATUSES).join(', ')
      orphan_sold = Inventory.statuses.values_at(*ORPHAN_SOLD_STATUSES).join(', ')
      created_on = Finance.local_date_sql('inventories.created_at')
      changed_on = Finance.local_date_sql('inventories.status_changed_at')

      <<~SQL.squish
        SELECT inventories.purchase_cost,
               CASE WHEN inventories.purchase_order_id IS NOT NULL
                    THEN COALESCE(purchase_orders.order_date, #{created_on})
                    ELSE #{created_on}
               END AS entered_on,
               LEAST(
                 rec.concluded_on,
                 CASE WHEN inventories.status IN (#{write_off}) THEN #{changed_on} END,
                 CASE WHEN inventories.status IN (#{orphan_sold}) AND inventories.sale_order_id IS NULL
                      THEN #{changed_on} END
               ) AS exited_on
        FROM inventories
        LEFT JOIN purchase_orders ON purchase_orders.id = inventories.purchase_order_id
        LEFT JOIN (#{SaleRecognition.sql}) rec ON rec.sale_order_id = inventories.sale_order_id
        WHERE purchase_orders.status IS DISTINCT FROM 'Canceled'
      SQL
    end

    def initialize(dates:)
      @dates = dates.map(&:to_date).uniq
    end

    def call
      return {} if @dates.empty?

      advances = sums(advances_sql)
      inventory = sums(inventory_sql)
      @dates.index_with do |date|
        { advances: advances.fetch(date, BigDecimal('0')), inventory: inventory.fetch(date, BigDecimal('0')) }
      end
    end

    private

    def sums(sql)
      conn.select_rows(sql).to_h { |date, value| [to_date(date), value.to_d] }
    end

    def dates_sql
      list = @dates.map { |date| conn.quote(date.iso8601) }.join(', ')
      "unnest(ARRAY[#{list}]::date[]) AS d(cutoff)"
    end

    # Dinero recibido a la fecha y no reembolsado a esa fecha, de órdenes no
    # concluidas a esa fecha y no devueltas (las canceladas sí cuentan).
    def advances_sql
      received = RECEIVED_PAYMENT_STATUSES.map { |s| conn.quote(s) }.join(', ')
      <<~SQL.squish
        SELECT d.cutoff, COALESCE(SUM(a.amount), 0)
        FROM #{dates_sql}
        LEFT JOIN (
          SELECT payments.amount, payments.paid_at, payments.status, payments.refunded_at, rec.concluded_on
          FROM payments
          JOIN sale_orders ON sale_orders.id = payments.sale_order_id
          LEFT JOIN (#{SaleRecognition.sql}) rec ON rec.sale_order_id = sale_orders.id
          WHERE payments.status IN (#{received})
            AND payments.paid_at IS NOT NULL
            AND sale_orders.status <> 'Returned'
        ) a ON a.paid_at <= d.cutoff
           AND NOT (a.status = 'Refunded' AND a.refunded_at IS NOT NULL AND a.refunded_at <= d.cutoff)
           AND (a.concluded_on IS NULL OR a.concluded_on > d.cutoff)
        GROUP BY d.cutoff
      SQL
    end

    def inventory_sql
      <<~SQL.squish
        SELECT d.cutoff, COALESCE(SUM(m.purchase_cost), 0)
        FROM #{dates_sql}
        LEFT JOIN (#{self.class.inventory_movements_sql}) m
          ON m.entered_on <= d.cutoff AND (m.exited_on IS NULL OR m.exited_on > d.cutoff)
        GROUP BY d.cutoff
      SQL
    end

    def to_date(value)
      value.is_a?(String) ? Date.parse(value) : value
    end

    def conn
      ActiveRecord::Base.connection
    end
  end
end
