# frozen_string_literal: true

module Dashboard
  class AnalyticsBuilder
    attr_reader :so_ytd, :start_date, :end_date

    def initialize(so_ytd:, start_date:, end_date:)
      @so_ytd = so_ytd
      @start_date = start_date
      @end_date = end_date
    end

    def category_charts_bundle
      paid_ytd_scope = Dashboard::Metrics.paid_scope(so_ytd)
      month_key_expr = month_group_expr('sale_orders', 'order_date')

      by_month_category_rows = SaleOrderItem.joins(:sale_order, :product)
                                            .merge(paid_ytd_scope)
                                            .group(Arel.sql(month_key_expr), 'products.category')
                                            .pluck(
                                              Arel.sql(month_key_expr),
                                              Arel.sql("COALESCE(NULLIF(products.category, ''), 'Uncategorized')"),
                                              Arel.sql("SUM(#{Dashboard::Metrics::REV_SQL})")
                                            )

      by_month_category_norm = by_month_category_rows.each_with_object({}) do |(month_key, category_name, revenue_total), acc|
        acc[[normalize_month_key(month_key), category_name.presence || 'Uncategorized']] = revenue_total.to_d
      end

      months_keys = months_between(start_date.beginning_of_month, end_date.end_of_month)
      category_totals = Hash.new(0.to_d)
      by_month_category_norm.each do |(_month_key, category), value|
        normalized_category = category.presence || 'Uncategorized'
        category_totals[normalized_category] += value.to_d
      end

      top_categories = category_totals.sort_by { |(_, value)| -value }.first(5).map(&:first)
      other_categories = category_totals.keys - top_categories

      monthly_by_category = {
        months: months_keys,
        series: build_monthly_series(months_keys, by_month_category_norm, top_categories, other_categories)
      }

      {
        monthly_by_category: monthly_by_category,
        brand_profit: profit_by_dimension(paid_ytd_scope, 'products.brand', fallback_label: 'Unbranded', key: :brands),
        category_profit: profit_by_dimension(paid_ytd_scope, 'products.category', fallback_label: 'Uncategorized', key: :categories)
      }
    end

    private

    def build_monthly_series(months_keys, normalized_rows, top_categories, other_categories)
      series = top_categories.map do |category|
        {
          name: category,
          data: months_keys.map { |month_key| (normalized_rows[[month_key, category]] || 0).to_d }
        }
      end

      if other_categories.any?
        series << {
          name: 'Others',
          data: months_keys.map { |month_key| other_categories.sum { |category| (normalized_rows[[month_key, category]] || 0).to_d } }
        }
      end

      series
    end

    def profit_by_dimension(scope, dimension, fallback_label:, key:)
      revenue_by_dimension = SaleOrderItem.joins(:sale_order, :product).merge(scope).group(dimension).sum(Arel.sql(Dashboard::Metrics::REV_SQL))
      cogs_by_dimension = SaleOrderItem.joins(:sale_order, :product).merge(scope).group(dimension).sum(Arel.sql(Dashboard::Metrics::COGS_SQL))
      dimensions = (revenue_by_dimension.keys + cogs_by_dimension.keys).uniq

      ranked = dimensions.map do |dimension_value|
        label = dimension_value.presence || fallback_label
        profit = revenue_by_dimension[dimension_value].to_d - cogs_by_dimension[dimension_value].to_d
        [label, profit]
      end.sort_by { |(_, profit)| -profit }.first(8)

      {
        key => ranked.map(&:first),
        profit: ranked.map(&:last)
      }
    end

    def months_between(start_value, end_value)
      current_month = start_value.to_date.beginning_of_month
      final_month = end_value.to_date.end_of_month
      months = []

      while current_month <= final_month
        months << current_month.strftime('%Y-%m')
        current_month = current_month.next_month.beginning_of_month
      end

      months
    end

    def normalize_month_key(value)
      value.is_a?(String) ? value : value.to_date.strftime('%Y-%m')
    end

    def month_group_expr(table_name, column_name)
      adapter = ActiveRecord::Base.connection.adapter_name.downcase
      if adapter.include?('sqlite')
        "strftime('%Y-%m', #{table_name}.#{column_name})"
      else
        "to_char(date_trunc('month', #{table_name}.#{column_name}), 'YYYY-MM')"
      end
    end
  end
end
