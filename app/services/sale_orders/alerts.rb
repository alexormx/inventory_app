# frozen_string_literal: true

module SaleOrders
  # Órdenes que requieren atención manual. Sólo lectura: nada aquí cancela,
  # cobra ni corrige una orden. Todo se agrega en SQL (el dyno tiene 512 MB).
  module Alerts
    STALE_PENDING_AFTER = 30.days
    TOLERANCE = 0.01

    # SQL fijo y valores por parámetro enlazado (?): nada se interpola en las
    # condiciones, así el escáner de seguridad puede verificarlas.
    PAID_SQL = 'COALESCE((SELECT SUM(p.amount) FROM payments p ' \
               "WHERE p.sale_order_id = sale_orders.id AND p.status = 'Completed'), 0)"
    OVERPAID_CONDITION = "#{PAID_SQL} > sale_orders.total_order_value + ?".freeze
    OVERPAID_ORDER = Arel.sql("#{PAID_SQL} - sale_orders.total_order_value DESC")
    SOLD_UNITS_CONDITION = 'EXISTS (SELECT 1 FROM inventories i WHERE i.sale_order_id = sale_orders.id AND i.status = ?)'

    module_function

    def paid_sql
      PAID_SQL
    end

    def held_sql
      statuses = Inventory.statuses.values_at('reserved', 'pre_reserved', 'sold').join(', ')
      "(SELECT COUNT(*) FROM inventories i WHERE i.sale_order_id = sale_orders.id AND i.status IN (#{statuses}))"
    end

    def with_figures(scope)
      scope.select("sale_orders.*, #{paid_sql} AS paid_amount, #{held_sql} AS held_units").includes(:user)
    end

    def stale_pending
      with_figures(SaleOrder.where(status: 'Pending').where(created_at: ...STALE_PENDING_AFTER.ago))
        .order(:created_at)
    end

    def overpaid
      with_figures(overpaid_scope).order(OVERPAID_ORDER)
    end

    def inconsistent
      with_figures(inconsistent_scope).order(:created_at)
    end

    def counts
      {
        stale_pending: SaleOrder.where(status: 'Pending').where(created_at: ...STALE_PENDING_AFTER.ago).count,
        overpaid: overpaid_scope.count,
        inconsistent: inconsistent_scope.count
      }
    end

    def overpaid_scope
      SaleOrder.where.not(status: 'Canceled').where(OVERPAID_CONDITION, TOLERANCE)
    end

    def inconsistent_scope
      SaleOrder.where(status: 'Pending').where(SOLD_UNITS_CONDITION, Inventory.statuses.fetch('sold'))
    end
  end
end
