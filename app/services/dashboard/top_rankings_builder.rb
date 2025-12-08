# frozen_string_literal: true

module Dashboard
  # Builds ranking data for top sellers, profitable products, inventory, categories, and customers.
  class TopRankingsBuilder
    REV_SQL = 'SUM(sale_order_items.quantity * sale_order_items.unit_price)'
    COGS_SQL = 'SUM(sale_order_items.quantity * COALESCE(sale_order_items.unit_cost, 0))'
    UNITS_SQL = 'SUM(sale_order_items.quantity)'

    attr_reader :now, :start_date, :end_date, :limit

    def initialize(start_date: nil, end_date: nil, limit: 10, time_reference: Time.current)
      @now = time_reference
      @start_date = start_date || now.beginning_of_year.to_date
      @end_date = end_date || now.end_of_day
      @limit = limit
    end

    # Returns all ranking data
    def call
      {
        top_sellers: top_sellers,
        top_profitable: top_profitable,
        top_inventory: top_inventory,
        top_categories: top_categories,
        top_customers: top_customers
      }
    end

    # Top products by revenue
    def top_sellers
      @top_sellers ||= product_rankings(:revenue)
    end

    # Top products by profit margin
    def top_profitable
      @top_profitable ||= product_rankings(:profit)
    end

    # Top products by inventory value
    def top_inventory
      @top_inventory ||= begin
        Product.left_joins(:inventories)
          .where(inventories: { status: :available })
          .group('products.id')
          .select(
            'products.id',
            'products.name',
            'products.sku',
            'products.current_stock',
            'products.avg_purchase_cost',
            'COUNT(inventories.id) AS inv_count',
            'products.current_stock * products.avg_purchase_cost AS inv_value'
          )
          .order(Arel.sql('products.current_stock * products.avg_purchase_cost DESC'))
          .limit(limit)
          .map do |p|
            {
              id: p.id,
              name: p.name,
              sku: p.sku,
              stock: p.current_stock,
              avg_cost: p.avg_purchase_cost.to_d,
              value: p.inv_value.to_d
            }
          end
      end
    end

    # Top categories by revenue
    def top_categories
      @top_categories ||= begin
        base_items
          .joins(product: :category)
          .group('categories.id', 'categories.name')
          .select(
            'categories.id',
            'categories.name',
            Arel.sql("#{REV_SQL} AS revenue"),
            Arel.sql("#{COGS_SQL} AS cogs"),
            Arel.sql("#{UNITS_SQL} AS units")
          )
          .order(Arel.sql("#{REV_SQL} DESC"))
          .limit(limit)
          .map do |row|
            revenue = row.revenue.to_d
            cogs = row.cogs.to_d
            profit = revenue - cogs
            margin = revenue.positive? ? ((profit / revenue) * 100).round(2) : 0

            {
              id: row.id,
              name: row.name,
              revenue: revenue,
              cogs: cogs,
              profit: profit,
              margin: margin,
              units: row.units.to_i
            }
          end
      end
    end

    # Top customers by revenue
    def top_customers
      @top_customers ||= begin
        base_orders
          .joins(:user, :sale_order_items)
          .group('users.id', 'users.email', 'users.name')
          .select(
            'users.id',
            'users.email',
            'users.name',
            Arel.sql("#{REV_SQL} AS revenue"),
            Arel.sql("#{COGS_SQL} AS cogs"),
            Arel.sql('COUNT(DISTINCT sale_orders.id) AS order_count'),
            Arel.sql("#{UNITS_SQL} AS units")
          )
          .order(Arel.sql("#{REV_SQL} DESC"))
          .limit(limit)
          .map do |row|
            revenue = row.revenue.to_d
            cogs = row.cogs.to_d

            {
              id: row.id,
              email: row.email,
              name: row.name,
              revenue: revenue,
              cogs: cogs,
              profit: revenue - cogs,
              orders: row.order_count.to_i,
              units: row.units.to_i
            }
          end
      end
    end

    private

    def product_rankings(sort_by)
      order_expr = sort_by == :profit ? "(#{REV_SQL} - #{COGS_SQL})" : REV_SQL

      base_items
        .joins(:product)
        .group('products.id', 'products.name', 'products.sku')
        .select(
          'products.id',
          'products.name',
          'products.sku',
          Arel.sql("#{REV_SQL} AS revenue"),
          Arel.sql("#{COGS_SQL} AS cogs"),
          Arel.sql("#{UNITS_SQL} AS units")
        )
        .order(Arel.sql("#{order_expr} DESC"))
        .limit(limit)
        .map do |row|
          revenue = row.revenue.to_d
          cogs = row.cogs.to_d
          profit = revenue - cogs
          margin = revenue.positive? ? ((profit / revenue) * 100).round(2) : 0

          {
            id: row.id,
            name: row.name,
            sku: row.sku,
            revenue: revenue,
            cogs: cogs,
            profit: profit,
            margin: margin,
            units: row.units.to_i
          }
        end
    end

    def base_orders
      SaleOrder.where(status: %w[Confirmed In\ Transit Delivered])
               .where(order_date: start_date..end_date)
    end

    def base_items
      SaleOrderItem.joins(:sale_order)
                   .where(sale_orders: { status: %w[Confirmed In\ Transit Delivered] })
                   .where(sale_orders: { order_date: start_date..end_date })
    end
  end
end
