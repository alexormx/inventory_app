# frozen_string_literal: true

module Dashboard
  # Antigüedad de saldos por cobrar y DSO (días de venta pendientes de cobro).
  #
  # El panel ya mostraba el total por cobrar, pero un total sano puede esconder
  # cartera vencida: $100k a 15 días y $100k a 120 días se veían igual.
  class ReceivablesAgingBuilder
    BUCKETS = {
      'current' => 'Por vencer',
      'days_1_30' => '1-30 días',
      'days_31_60' => '31-60 días',
      'days_61_90' => '61-90 días',
      'days_90_plus' => '+90 días'
    }.freeze

    def initialize(net_revenue: nil, period_days: nil, today: Time.zone.today)
      @net_revenue = net_revenue
      @period_days = period_days
      @today = today
    end

    def call
      # Se agrega en SQL en vez de traer las órdenes: la cartera abierta crece
      # sin techo y el dyno de producción es de 512MB.
      rows = SaleOrder.open_receivables
                      .group(Arel.sql(bucket_sql))
                      .pluck(Arel.sql(bucket_sql), Arel.sql('COUNT(*)'), Arel.sql("SUM(#{SaleOrder::BALANCE_SQL})"))
                      .to_h { |key, count, amount| [key, { count: count.to_i, amount: amount.to_d }] }

      buckets = BUCKETS.to_h do |key, label|
        row = rows[key] || { count: 0, amount: 0.to_d }
        [key, row.merge(label: label)]
      end

      total = buckets.values.sum { |b| b[:amount] }
      overdue = total - buckets['current'][:amount]

      {
        buckets: buckets,
        total: total,
        overdue: overdue,
        overdue_ratio: total.positive? ? (overdue / total) : nil,
        dso: dso(total)
      }
    end

    private

    attr_reader :net_revenue, :period_days, :today

    # Cuando no hay due_date se usa order_date: una orden a crédito sin plazo
    # capturado envejece desde que se vendió, no desde nunca.
    def bucket_sql
      days = "(#{SaleOrder.connection.quote(today)}::date - COALESCE(sale_orders.due_date, sale_orders.order_date))"
      <<~SQL.squish
        CASE
          WHEN #{days} <= 0 THEN 'current'
          WHEN #{days} <= 30 THEN 'days_1_30'
          WHEN #{days} <= 60 THEN 'days_31_60'
          WHEN #{days} <= 90 THEN 'days_61_90'
          ELSE 'days_90_plus'
        END
      SQL
    end

    # Days Sales Outstanding: cuántos días de venta del periodo equivalen a la
    # cartera abierta. Se compara contra los términos de crédito otorgados.
    def dso(total)
      return nil if net_revenue.to_d.zero? || period_days.to_i <= 0

      ((total / net_revenue.to_d) * period_days).round(1)
    end
  end
end
