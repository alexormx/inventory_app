# frozen_string_literal: true

module SaleOrders
  # Órdenes que requieren atención manual. Sólo lectura: nada aquí cancela,
  # cobra ni corrige una orden. Todo se agrega en SQL (el dyno tiene 512 MB).
  module Alerts
    STALE_PENDING_AFTER = 30.days
    TOLERANCE = 0.01

    module_function

    def paid_sql
      'COALESCE((SELECT SUM(p.amount) FROM payments p ' \
        "WHERE p.sale_order_id = sale_orders.id AND p.status = 'Completed'), 0)"
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
      with_figures(SaleOrder.where.not(status: 'Canceled').where("#{paid_sql} > sale_orders.total_order_value + #{TOLERANCE}"))
        .order(Arel.sql("#{paid_sql} - sale_orders.total_order_value DESC"))
    end

    def inconsistent
      sold = Inventory.statuses.fetch('sold')
      with_figures(SaleOrder.where(status: 'Pending')
                            .where("EXISTS (SELECT 1 FROM inventories i WHERE i.sale_order_id = sale_orders.id AND i.status = #{sold})"))
        .order(:created_at)
    end

    def counts
      {
        stale_pending: SaleOrder.where(status: 'Pending').where(created_at: ...STALE_PENDING_AFTER.ago).count,
        overpaid: SaleOrder.where.not(status: 'Canceled').where("#{paid_sql} > sale_orders.total_order_value + #{TOLERANCE}").count,
        inconsistent: SaleOrder.where(status: 'Pending')
                               .where("EXISTS (SELECT 1 FROM inventories i WHERE i.sale_order_id = sale_orders.id AND i.status = #{Inventory.statuses.fetch('sold')})")
                               .count
      }
    end
  end
end
