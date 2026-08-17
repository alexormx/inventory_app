# frozen_string_literal: true

module Dashboard
  module Metrics
    REV_SQL = SaleOrderItem::LINE_REVENUE_SQL
    COGS_SQL = SaleOrderItem::LINE_COGS_SQL
    UNITS_SQL = 'COALESCE(sale_order_items.quantity, 0)'
    # Mismo concepto que las métricas de venta por producto, así que comparten
    # una sola definición en el modelo que es dueño de la semántica de estados.
    SALE_STATUSES = SaleOrder::ACTIVE_SALE_STATUSES
    LOST_STATUSES = %w[Canceled Returned].freeze

    module_function

    def paid_scope(scope)
      scope.where(status: SALE_STATUSES)
    end

    def revenue_total(scope)
      line_items(scope).sum(Arel.sql(REV_SQL)).to_d
    end

    # El descuento vive en la orden, no en la línea, así que no puede sumarse
    # dentro de REV_SQL sin multiplicarlo por el número de líneas.
    def order_discount_total(scope)
      scope.sum(:discount).to_d
    end

    # Ingreso reconciliado con lo que factura la orden. Los desgloses por
    # producto o categoría siguen usando revenue_total porque un descuento de
    # orden no es atribuible a una línea concreta.
    def net_revenue_total(scope)
      revenue_total(scope) - order_discount_total(scope)
    end

    def cogs_total(scope)
      line_items_with_product(scope).sum(Arel.sql(COGS_SQL)).to_d
    end

    # Requiere un scope SIN filtrar por estado: el scope base del panel excluye
    # 'Canceled' por defecto, y con él la tasa siempre daría cero.
    def lost_orders_stats(unfiltered_scope)
      counts = unfiltered_scope.where(status: LOST_STATUSES).group(:status).count
      canceled = counts['Canceled'].to_i
      returned = counts['Returned'].to_i
      total = unfiltered_scope.count

      {
        canceled: canceled,
        returned: returned,
        total: total,
        rate: total.positive? ? ((canceled + returned).to_d / total) : nil
      }
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
