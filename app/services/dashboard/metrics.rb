# frozen_string_literal: true

module Dashboard
  module Metrics
    REV_SQL = 'COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)'
    COGS_SQL = 'COALESCE(products.average_purchase_cost, 0) * COALESCE(sale_order_items.quantity, 0)'
    UNITS_SQL = 'COALESCE(sale_order_items.quantity, 0)'
    SALE_STATUSES = ['Confirmed', 'Preparing', 'In Transit', 'Delivered'].freeze

    module_function

    def paid_scope(scope)
      scope.where(status: SALE_STATUSES)
    end

    def revenue_total(scope)
      line_items(scope).sum(Arel.sql(REV_SQL)).to_d
    end

    def cogs_total(scope)
      line_items_with_product(scope).sum(Arel.sql(COGS_SQL)).to_d
    end

    def grouped_revenue(scope, group_expr)
      line_items(scope).group(Arel.sql(group_expr)).sum(Arel.sql(REV_SQL))
    end

    def grouped_cogs(scope, group_expr)
      line_items_with_product(scope).group(Arel.sql(group_expr)).sum(Arel.sql(COGS_SQL))
    end

    def category_rows(scope, metric:, limit: 10)
      paid = paid_scope(scope)
      revenue_by_category = line_items_with_product(paid).group('products.category').sum(Arel.sql(REV_SQL))

      rows = if metric == 'profit'
               cogs_by_category = line_items_with_product(paid).group('products.category').sum(Arel.sql(COGS_SQL))
               (revenue_by_category.keys + cogs_by_category.keys).uniq.map do |category|
                 revenue = revenue_by_category[category].to_d
                 cogs = cogs_by_category[category].to_d
                 {
                   category: category.presence || 'Uncategorized',
                   value: revenue - cogs,
                   revenue: revenue,
                   cogs: cogs,
                   profit: revenue - cogs
                 }
               end
             else
               revenue_by_category.map do |category, value|
                 {
                   category: category.presence || 'Uncategorized',
                   value: value.to_d,
                   revenue: value.to_d
                 }
               end
             end

      rows.sort_by { |row| -row[:value].to_d }.first(limit)
    end

    def customer_sales_rows(scope, limit: 10)
      SaleOrderItem.joins(sale_order: :user)
                   .merge(paid_scope(scope))
                   .group('users.id', 'users.name')
                   .select("users.id AS user_id, users.name, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{REV_SQL}) AS revenue")
                   .order('revenue DESC')
                   .limit(limit)
                   .map do |row|
        {
          user_id: row.attributes['user_id'].to_i,
          name: row.name.presence || row.attributes['user_id'],
          orders_count: row.attributes['orders_count'].to_i,
          revenue: row.attributes['revenue'].to_d
        }
      end
    end

    def customer_sales_map(scope)
      SaleOrderItem.joins(sale_order: :user)
                   .merge(paid_scope(scope))
                   .group('users.id')
                   .select("users.id AS user_id, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{REV_SQL}) AS revenue")
                   .index_by { |row| row.attributes['user_id'].to_i }
                   .transform_values do |row|
        {
          orders_count: row.attributes['orders_count'].to_i,
          revenue: row.attributes['revenue'].to_d
        }
      end
    end

    def line_items(scope)
      SaleOrderItem.joins(:sale_order).merge(scope)
    end

    def line_items_with_product(scope)
      SaleOrderItem.joins(:sale_order, :product).merge(scope)
    end
  end
end
