# frozen_string_literal: true

module Dashboard
  # Calculates KPIs (Key Performance Indicators) for the admin dashboard.
  # Handles YTD, Last Year, and All Time comparisons.
  class KpiCalculator
    # SQL fragments for revenue and COGS calculations
    REV_SQL = 'SUM(sale_order_items.quantity * sale_order_items.unit_price)'
    COGS_SQL = 'SUM(sale_order_items.quantity * COALESCE(sale_order_items.unit_cost, 0))'

    attr_reader :now, :ytd_start, :ly_start, :ly_end

    def initialize(time_reference: Time.current)
      @now = time_reference
      @ytd_start = @now.beginning_of_year
      @ly_start = @now.beginning_of_year - 1.year
      @ly_end = @ly_start.end_of_year
    end

    # Returns a hash with all KPI data for the dashboard
    def call
      {
        ytd: ytd_kpis,
        last_year: last_year_kpis,
        all_time: all_time_kpis,
        deltas: calculate_deltas
      }
    end

    private

    # === YTD KPIs ===
    def ytd_kpis
      @ytd_kpis ||= begin
        scope = base_scope.where(order_date: ytd_start..now.end_of_day)
        calculate_kpis(scope, 'ytd')
      end
    end

    # === Last Year KPIs ===
    def last_year_kpis
      @last_year_kpis ||= begin
        scope = base_scope.where(order_date: ly_start..ly_end)
        calculate_kpis(scope, 'ly')
      end
    end

    # === All Time KPIs ===
    def all_time_kpis
      @all_time_kpis ||= calculate_kpis(base_scope, 'all')
    end

    def calculate_kpis(scope, period_key)
      joined = scope.joins(:sale_order_items)

      raw = joined.pick(
        Arel.sql(REV_SQL),
        Arel.sql(COGS_SQL),
        Arel.sql('COUNT(DISTINCT sale_orders.id)'),
        Arel.sql('SUM(sale_order_items.quantity)')
      )

      revenue = raw[0].to_d
      cogs = raw[1].to_d
      orders = raw[2].to_i
      units = raw[3].to_i
      profit = revenue - cogs
      margin = revenue.positive? ? ((profit / revenue) * 100).round(2) : 0

      {
        revenue: revenue,
        cogs: cogs,
        profit: profit,
        margin: margin,
        orders: orders,
        units: units,
        aov: orders.positive? ? (revenue / orders).round(2) : 0,
        period: period_key
      }
    end

    def calculate_deltas
      ytd = ytd_kpis
      ly = last_year_kpis

      {
        revenue: delta_value(ytd[:revenue], ly[:revenue]),
        profit: delta_value(ytd[:profit], ly[:profit]),
        orders: delta_value(ytd[:orders], ly[:orders]),
        margin: delta_points(ytd[:margin], ly[:margin]),
        aov: delta_value(ytd[:aov], ly[:aov])
      }
    end

    def delta_value(current, previous)
      return nil if previous.nil? || previous.zero?

      ((current - previous) / previous.to_d * 100).round(1)
    end

    def delta_points(current, previous)
      return nil if previous.nil?

      (current - previous).round(2)
    end

    def base_scope
      SaleOrder.where(status: ['Confirmed', 'In Transit', 'Delivered'])
    end
  end
end
