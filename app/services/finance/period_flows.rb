# frozen_string_literal: true

module Finance
  # Flujos y utilidad por periodo (mes o año), agregados en SQL. Ver las filas
  # "Utilidad" y "Flujo" del spec de finanzas mensual.
  #
  #   Finance::PeriodFlows.new(range: Date..Date, grain: :month).call
  #   # => { Date(inicio del periodo) => { sales:, sales_count:, discounts:,
  #   #      sale_refunds:, cogs:, cash_in:, purchases:, refunds: } }
  #
  # Sólo aparecen los periodos con datos; dentro de un periodo, las llaves sin
  # datos valen 0.
  class PeriodFlows
    GRAINS = %i[month year].freeze
    KEYS = %i[sales sales_count discounts sale_refunds cogs cash_in purchases refunds].freeze
    INTEGER_KEYS = %i[sales_count].freeze

    def initialize(range:, grain: :month)
      raise ArgumentError, "grain inválido: #{grain.inspect}" unless GRAINS.include?(grain)

      @from = range.begin
      @to = range.exclude_end? ? range.end - 1 : range.end
      @grain = grain
    end

    def call
      rows = conn.select_all(sql).to_a
      rows.each_with_object({}) do |row, result|
        period = to_date(row['period'])
        bucket = result[period] ||= empty_bucket
        key = row['metric'].to_sym
        bucket[key] += INTEGER_KEYS.include?(key) ? row['value'].to_i : row['value'].to_d
      end.sort.to_h
    end

    private

    def empty_bucket
      KEYS.index_with { |key| INTEGER_KEYS.include?(key) ? 0 : BigDecimal('0') }
    end

    def sql
      <<~SQL.squish
        #{lines_sql}
        UNION ALL #{orders_sql}
        UNION ALL #{sale_refunds_sql}
        UNION ALL #{refunds_sql}
        UNION ALL #{cash_in_sql}
        UNION ALL #{purchase_orders_sql}
        UNION ALL #{manual_inventory_sql}
      SQL
    end

    # Ventas y costo por línea de las órdenes concluidas en el periodo.
    def lines_sql
      period = bucket('rec.concluded_on')
      <<~SQL.squish
        SELECT p.period, m.metric, m.value
        FROM (
          SELECT #{period} AS period,
                 SUM(#{SaleOrderItem::LINE_REVENUE_SQL}) AS sales,
                 SUM(#{SaleOrderItem::LINE_COGS_SQL}) AS cogs
          FROM sale_order_items
          JOIN sale_orders ON sale_orders.id = sale_order_items.sale_order_id
          JOIN (#{SaleRecognition.sql}) rec ON rec.sale_order_id = sale_orders.id
          LEFT JOIN products ON products.id = sale_order_items.product_id
          WHERE #{in_range('rec.concluded_on')}
          GROUP BY 1
        ) p
        CROSS JOIN LATERAL (VALUES ('sales', p.sales), ('cogs', p.cogs)) AS m(metric, value)
      SQL
    end

    # Conteo y descuento por orden, aparte para no multiplicarlo por línea.
    def orders_sql
      period = bucket('rec.concluded_on')
      <<~SQL.squish
        SELECT p.period, m.metric, m.value
        FROM (
          SELECT #{period} AS period,
                 COUNT(*) AS sales_count,
                 SUM(COALESCE(sale_orders.discount, 0)) AS discounts
          FROM sale_orders
          JOIN (#{SaleRecognition.sql}) rec ON rec.sale_order_id = sale_orders.id
          WHERE #{in_range('rec.concluded_on')}
          GROUP BY 1
        ) p
        CROSS JOIN LATERAL (VALUES ('sales_count', p.sales_count::numeric), ('discounts', p.discounts))
          AS m(metric, value)
      SQL
    end

    # Reembolsos de órdenes ya concluidas a la fecha del reembolso.
    def sale_refunds_sql
      <<~SQL.squish
        SELECT #{bucket('payments.refunded_at')}, 'sale_refunds', SUM(payments.amount)
        FROM payments
        JOIN (#{SaleRecognition.sql}) rec ON rec.sale_order_id = payments.sale_order_id
        WHERE payments.status = 'Refunded'
          AND #{in_range('payments.refunded_at')}
          AND rec.concluded_on <= payments.refunded_at
        GROUP BY 1
      SQL
    end

    def refunds_sql
      <<~SQL.squish
        SELECT #{bucket('payments.refunded_at')}, 'refunds', SUM(payments.amount)
        FROM payments
        WHERE payments.status = 'Refunded' AND #{in_range('payments.refunded_at')}
        GROUP BY 1
      SQL
    end

    def cash_in_sql
      received = RECEIVED_PAYMENT_STATUSES.map { |s| conn.quote(s) }.join(', ')
      <<~SQL.squish
        SELECT #{bucket('payments.paid_at')}, 'cash_in', SUM(payments.amount)
        FROM payments
        WHERE payments.status IN (#{received}) AND #{in_range('payments.paid_at')}
        GROUP BY 1
      SQL
    end

    def purchase_orders_sql
      <<~SQL.squish
        SELECT #{bucket('purchase_orders.order_date')}, 'purchases',
               SUM(COALESCE(NULLIF(purchase_orders.total_cost_mxn, 0), purchase_orders.total_order_cost, 0))
        FROM purchase_orders
        WHERE purchase_orders.status <> 'Canceled' AND #{in_range('purchase_orders.order_date')}
        GROUP BY 1
      SQL
    end

    # Altas manuales: piezas sin orden de compra, por la fecha local de created_at.
    def manual_inventory_sql
      created_on = Finance.local_date_sql('inventories.created_at')
      <<~SQL.squish
        SELECT #{bucket(created_on)}, 'purchases', SUM(inventories.purchase_cost)
        FROM inventories
        WHERE inventories.purchase_order_id IS NULL
          AND inventories.purchase_order_item_id IS NULL
          AND inventories.purchase_cost > 0
          AND #{in_range(created_on)}
        GROUP BY 1
      SQL
    end

    def bucket(date_sql)
      "DATE_TRUNC('#{@grain}', #{date_sql})::date"
    end

    def in_range(date_sql)
      "#{date_sql} BETWEEN #{conn.quote(@from)}::date AND #{conn.quote(@to)}::date"
    end

    def to_date(value)
      value.is_a?(String) ? Date.parse(value) : value
    end

    def conn
      ActiveRecord::Base.connection
    end
  end
end
