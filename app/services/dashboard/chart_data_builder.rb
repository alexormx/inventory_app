# frozen_string_literal: true

module Dashboard
  # Builds chart data for the admin dashboard.
  # Supports revenue, profit, orders over time (monthly/yearly).
  class ChartDataBuilder
    REV_SQL = 'SUM(sale_order_items.quantity * sale_order_items.unit_price)'
    COGS_SQL = 'SUM(sale_order_items.quantity * COALESCE(sale_order_items.unit_cost, 0))'

    attr_reader :now, :date_range, :start_date, :end_date

    def initialize(date_range: 'ytd', start_date: nil, end_date: nil, time_reference: Time.current)
      @now = time_reference
      @date_range = date_range
      @start_date, @end_date = compute_date_range(date_range, start_date, end_date)
    end

    # Returns chart data for the given period
    def call
      {
        monthly_revenue: monthly_revenue_data,
        monthly_profit: monthly_profit_data,
        monthly_orders: monthly_orders_data,
        yearly_comparison: yearly_comparison_data,
        labels: chart_labels
      }
    end

    # Build monthly revenue/profit/orders arrays aligned to months_between
    def monthly_revenue_data
      build_monthly_metric(:revenue)
    end

    def monthly_profit_data
      build_monthly_metric(:profit)
    end

    def monthly_orders_data
      build_monthly_metric(:orders)
    end

    def yearly_comparison_data
      current_year = now.year
      years = ((current_year - 2)..current_year).to_a

      years.map do |year|
        year_start = Date.new(year, 1, 1)
        year_end = year == current_year ? now.to_date : Date.new(year, 12, 31)

        scope = base_scope.where(order_date: year_start..year_end.end_of_day)
        joined = scope.joins(:sale_order_items)

        raw = joined.pick(
          Arel.sql(REV_SQL),
          Arel.sql(COGS_SQL),
          Arel.sql('COUNT(DISTINCT sale_orders.id)')
        )

        revenue = raw[0].to_d
        cogs = raw[1].to_d

        {
          year: year,
          revenue: revenue,
          cogs: cogs,
          profit: revenue - cogs,
          orders: raw[2].to_i
        }
      end
    end

    def chart_labels
      months_between(start_date, end_date).map do |ym|
        Date.parse("#{ym}-01").strftime('%b %Y')
      end
    end

    private

    def build_monthly_metric(metric)
      months = months_between(start_date, end_date)
      grouped = grouped_monthly_data

      months.map do |ym|
        data = grouped[ym] || { revenue: 0, cogs: 0, orders: 0 }
        case metric
        when :revenue then data[:revenue].to_f
        when :profit then (data[:revenue] - data[:cogs]).to_f
        when :orders then data[:orders].to_i
        end
      end
    end

    def grouped_monthly_data
      @grouped_monthly_data ||= begin
        scope = base_scope.where(order_date: start_date..end_date)
        joined = scope.joins(:sale_order_items)

        month_expr = month_group_expr

        raw = joined
              .select(
                Arel.sql("#{month_expr} AS period_month"),
                Arel.sql("#{REV_SQL} AS revenue"),
                Arel.sql("#{COGS_SQL} AS cogs"),
                Arel.sql('COUNT(DISTINCT sale_orders.id) AS orders')
              )
              .group(Arel.sql(month_expr))

        raw.each_with_object({}) do |row, hash|
          key = normalize_month_key(row.period_month)
          hash[key] = {
            revenue: row.revenue.to_d,
            cogs: row.cogs.to_d,
            orders: row.orders.to_i
          }
        end
      end
    end

    def compute_date_range(range_key, start_param, end_param)
      case range_key
      when 'last_30'
        [now.to_date - 30, now.end_of_day]
      when 'last_90'
        [now.to_date - 90, now.end_of_day]
      when 'this_year'
        [now.beginning_of_year.to_date, now.end_of_day]
      when 'custom'
        s = start_param.present? ? Date.parse(start_param) : now.beginning_of_year.to_date
        e = end_param.present? ? Time.zone.parse(end_param).end_of_day : now.end_of_day
        [s, e]
      else # 'ytd'
        [now.beginning_of_year.to_date, now.end_of_day]
      end
    rescue ArgumentError
      [now.beginning_of_year.to_date, now.end_of_day]
    end

    def base_scope
      SaleOrder.where(status: ['Confirmed', 'In Transit', 'Delivered'])
    end

    def db_adapter
      @db_adapter ||= ActiveRecord::Base.connection.adapter_name.to_s.downcase
    end

    def month_group_expr
      col = 'sale_orders.order_date'
      if db_adapter.include?('sqlite')
        "strftime('%Y-%m-01', #{col})"
      else
        "DATE_TRUNC('month', #{col})"
      end
    end

    def normalize_month_key(key)
      if key.is_a?(String)
        key[0, 7]
      elsif key.respond_to?(:to_date)
        key.to_date.strftime('%Y-%m')
      else
        key.to_s[0, 7]
      end
    end

    def months_between(start_d, end_d)
      start_date = start_d.to_date.beginning_of_month
      end_date = end_d.to_date.end_of_month
      months = []
      d = start_date
      while d <= end_date
        months << d.strftime('%Y-%m')
        d = d.next_month.beginning_of_month
      end
      months
    end
  end
end
