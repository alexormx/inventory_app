# frozen_string_literal: true

module Dashboard
  class RankingsBuilder
    attr_reader :now, :so_scope, :so_ytd, :so_ytd_paid, :start_date, :end_date

    def initialize(now:, so_scope:, so_ytd:, so_ytd_paid:, start_date:, end_date:)
      @now = now
      @so_scope = so_scope
      @so_ytd = so_ytd
      @so_ytd_paid = so_ytd_paid
      @start_date = start_date
      @end_date = end_date
    end

    def top_users_bundle
      top_users_all = Dashboard::Metrics.customer_sales_rows(so_scope.where(status: Dashboard::Metrics::SALE_STATUSES), limit: 10)
      top_users_range = Dashboard::Metrics.customer_sales_rows(so_ytd.where(status: Dashboard::Metrics::SALE_STATUSES), limit: 10)

      ly_start = now.beginning_of_year - 1.year
      so_last_year = so_scope.where(order_date: ly_start..ly_start.end_of_year, status: Dashboard::Metrics::SALE_STATUSES)
      top_users_last_year = Dashboard::Metrics.customer_sales_rows(so_last_year, limit: 10)

      range_prev_start = start_date.prev_year
      range_prev_end = end_date.prev_year
      so_prev_range = so_scope.where(order_date: range_prev_start..range_prev_end, status: Dashboard::Metrics::SALE_STATUSES)
      prev_map = Dashboard::Metrics.customer_sales_map(so_prev_range)

      top_users_ytd_vs_prev = top_users_range.map do |user_row|
        prev = prev_map[user_row[:user_id]] || { orders_count: 0, revenue: 0.to_d }
        delta = prev[:revenue].to_d.positive? ? ((user_row[:revenue] - prev[:revenue]) / prev[:revenue]) : nil

        user_row.merge(
          prev_orders_count: prev[:orders_count],
          prev_revenue: prev[:revenue],
          revenue_delta_ratio: delta
        )
      end

      top_orders_ytd = so_ytd_paid.joins(:user)
                                  .select('sale_orders.id, sale_orders.total_order_value, sale_orders.order_date, sale_orders.status, users.name AS user_name')
                                  .order(total_order_value: :desc)
                                  .limit(5)

      {
        top_users_all: top_users_all,
        top_users_range: top_users_range,
        top_users_last_year: top_users_last_year,
        top_users_ytd_vs_prev: top_users_ytd_vs_prev,
        top_orders_ytd: top_orders_ytd
      }
    end

    def top_categories_bundle
      ly_start = now.beginning_of_year - 1.year
      so_prev = so_scope.where(order_date: ly_start..ly_start.end_of_year, status: Dashboard::Metrics::SALE_STATUSES)
      paid_ytd = so_ytd.where(status: Dashboard::Metrics::SALE_STATUSES)
      paid_all = so_scope.where(status: Dashboard::Metrics::SALE_STATUSES)

      {
        top_categories_ytd: Dashboard::Metrics.category_rows(paid_ytd, metric: 'rev', limit: 10),
        top_categories_profit_ytd: Dashboard::Metrics.category_rows(paid_ytd, metric: 'profit', limit: 10),
        top_categories_last_year: Dashboard::Metrics.category_rows(so_prev, metric: 'rev', limit: 10),
        top_categories_profit_last_year: Dashboard::Metrics.category_rows(so_prev, metric: 'profit', limit: 10),
        top_categories_all_time: Dashboard::Metrics.category_rows(paid_all, metric: 'rev', limit: 10),
        top_categories_profit_all_time: Dashboard::Metrics.category_rows(paid_all, metric: 'profit', limit: 10)
      }
    end

    def customers_rows(scope:, metric:, limit: 10)
      reserved_statuses = %i[reserved pre_reserved pre_sold]
      sales_rows = Dashboard::Metrics.customer_sales_rows(scope, limit: limit)
      reserved_rows = reserved_rows_for(scope, reserved_statuses)

      case metric
      when 'reserved'
        reserved_rows.sort_by { |row| -row[:reserved_value] }.first(limit)
      when 'combined'
        combine_sales_reserved(sales_rows, reserved_rows).first(limit)
      else
        sales_rows.sort_by { |row| -row[:revenue] }.first(limit)
      end
    end

    private

    def reserved_rows_for(scope, statuses)
      Inventory.joins(sale_order: :user)
               .merge(scope)
               .where(status: statuses)
               .group('users.id', 'users.name')
               .select('users.id AS user_id, users.name, COUNT(inventories.id) AS units_reserved, SUM(inventories.purchase_cost) AS reserved_value')
               .map do |row|
        {
          user_id: row.attributes['user_id'].to_i,
          name: row.name.presence || row.attributes['user_id'],
          units_reserved: row.attributes['units_reserved'].to_i,
          reserved_value: row.attributes['reserved_value'].to_d
        }
      end
    end

    def combine_sales_reserved(sales_rows, reserved_rows)
      sales_map = (sales_rows || []).index_by { |row| row[:user_id] }
      reserved_map = (reserved_rows || []).index_by { |row| row[:user_id] }

      (sales_map.keys + reserved_map.keys).uniq.map do |user_id|
        sales = sales_map[user_id]
        reserved = reserved_map[user_id]
        revenue = sales ? sales[:revenue].to_d : 0.to_d
        reserved_value = reserved ? reserved[:reserved_value].to_d : 0.to_d

        {
          user_id: user_id,
          name: sales&.dig(:name).presence || reserved&.dig(:name).presence || user_id,
          orders_count: sales ? sales[:orders_count].to_i : 0,
          revenue: revenue,
          units_reserved: reserved ? reserved[:units_reserved].to_i : 0,
          reserved_value: reserved_value,
          total: revenue + reserved_value
        }
      end.sort_by { |row| -row[:total] }
    end
  end
end
