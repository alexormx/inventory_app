# frozen_string_literal: true

module Finance
  # Fecha de conclusión de cada venta: el paid_at del pago con el que la suma
  # acumulada alcanza total_order_value (ver spec de finanzas mensual).
  module SaleRecognition
    module_function

    # SELECT sin punto y coma: una fila por orden reconocida
    # (sale_order_id string, concluded_on date). Se usa como subconsulta.
    def sql
      conn = ActiveRecord::Base.connection
      received = RECEIVED_PAYMENT_STATUSES.map { |s| conn.quote(s) }.join(', ')
      excluded = %w[Canceled Returned].map { |s| conn.quote(s) }.join(', ')
      active = SaleOrder::ACTIVE_SALE_STATUSES.map { |s| conn.quote(s) }.join(', ')

      <<~SQL.squish
        WITH running AS (
          SELECT p.sale_order_id, p.paid_at,
                 SUM(p.amount) OVER (
                   PARTITION BY p.sale_order_id
                   ORDER BY p.paid_at, p.id
                   ROWS UNBOUNDED PRECEDING
                 ) AS cumulative
          FROM payments p
          WHERE p.status IN (#{received}) AND p.paid_at IS NOT NULL
        )
        SELECT so.id AS sale_order_id, MIN(running.paid_at) AS concluded_on
        FROM sale_orders so
        JOIN running ON running.sale_order_id = so.id
        WHERE so.status NOT IN (#{excluded})
          AND running.cumulative >= so.total_order_value
        GROUP BY so.id
        UNION ALL
        SELECT so.id AS sale_order_id, so.order_date AS concluded_on
        FROM sale_orders so
        JOIN users u ON u.id = so.user_id
        WHERE so.status IN (#{active})
          AND NOT (u.credit_enabled OR so.credit_override)
          AND NOT EXISTS (
            SELECT 1 FROM payments p2
            WHERE p2.sale_order_id = so.id AND p2.status IN (#{received})
          )
      SQL
    end

    def concluded_on_by_order
      ActiveRecord::Base.connection.select_rows(sql).to_h.transform_values { |date| to_date(date) }
    end

    def to_date(value)
      value.is_a?(String) ? Date.parse(value) : value
    end
  end
end
