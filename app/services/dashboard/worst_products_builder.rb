# frozen_string_literal: true

module Dashboard
  # Calculates "worst" product metrics: margin, rotation, DOH, immobilized capital.
  # Used to identify products that need attention/optimization.
  class WorstProductsBuilder
    attr_reader :now, :start_date, :end_date, :weights, :limit

    def initialize(start_date: nil, end_date: nil, weights: {}, limit: 10, time_reference: Time.current)
      @now = time_reference
      @start_date = start_date || now.beginning_of_year.to_date
      @end_date = end_date || now.end_of_day
      @weights = normalize_weights(weights)
      @limit = limit
    end

    # Returns all worst product data
    def call
      per_product = build_per_product_metrics

      {
        worst_margin: worst_by(:margin_pct, per_product),
        worst_rotation: worst_by(:rotation, per_product),
        top_doh: top_doh(per_product),
        top_immobilized: top_immobilized(per_product),
        worst_score: worst_scored(per_product),
        global_metrics: global_metrics(per_product)
      }
    end

    private

    def normalize_weights(w)
      {
        margin: (w[:margin] || w[:w1] || 0.4).to_f,
        rotation: (w[:rotation] || w[:w2] || 0.2).to_f,
        doh: (w[:doh] || w[:w3] || 0.2).to_f,
        capital: (w[:capital] || w[:w4] || 0.2).to_f
      }
    end

    def build_per_product_metrics
      # Gather all products with their inventory and sales data
      products_data = {}

      # Get available inventory counts and costs
      inventory_data = Inventory.where(status: :available)
                                .joins(:product)
                                .group('products.id')
                                .select(
                                  'products.id',
                                  'COUNT(inventories.id) AS inv_count',
                                  'SUM(inventories.purchase_cost) AS total_cost'
                                )

      inventory_data.each do |row|
        products_data[row.id] ||= empty_product_hash
        products_data[row.id][:inv_count] = row.inv_count.to_i
        products_data[row.id][:inv_total_cost] = row.total_cost.to_d
      end

      # Get sales data
      sales_scope = SaleOrderItem.joins(:sale_order, :product)
                                 .where(sale_orders: { status: ['Confirmed', 'In Transit', 'Delivered'] })
                                 .where(sale_orders: { order_date: start_date..end_date })
                                 .group('products.id')
                                 .select(
                                   'products.id',
                                   'SUM(sale_order_items.quantity) AS units_sold',
                                   'SUM(sale_order_items.quantity * COALESCE(sale_order_items.unit_final_price, 0)) AS revenue',
                                   'SUM(sale_order_items.quantity * COALESCE(sale_order_items.unit_cost, 0)) AS cogs'
                                 )

      sales_scope.each do |row|
        products_data[row.id] ||= empty_product_hash
        products_data[row.id][:units_sold] = row.units_sold.to_i
        products_data[row.id][:revenue] = row.revenue.to_d
        products_data[row.id][:cogs] = row.cogs.to_d
      end

      # Get product info
      product_ids = products_data.keys
      return [] if product_ids.empty?

      products = Product.where(id: product_ids).index_by(&:id)
      period_months = months_in_period

      products_data.map do |product_id, data|
        product = products[product_id]
        next unless product

        units_sold = data[:units_sold]
        revenue = data[:revenue]
        cogs = data[:cogs]
        inv_count = data[:inv_count]
        inv_cost = data[:inv_total_cost]
        apc = product.average_purchase_cost.to_d

        profit = revenue - cogs
        margin_pct = revenue.positive? ? ((profit / revenue) * 100).round(2) : nil
        avg_monthly = period_months.positive? ? (units_sold.to_f / period_months).round(2) : 0
        rotation = inv_count.positive? && avg_monthly.positive? ? (units_sold.to_f / inv_count).round(2) : 0
        doh = avg_monthly.positive? ? (inv_count.to_f / (avg_monthly / 30.0)).round(1) : Float::INFINITY
        immobilized = inv_cost.positive? ? inv_cost : (inv_count * apc)

        {
          id: product_id,
          name: product.product_name,
          sku: product.product_sku,
          units_sold: units_sold,
          revenue: revenue,
          cogs: cogs,
          margin_pct: margin_pct,
          rotation: rotation,
          doh: doh,
          avg_monthly_sales: avg_monthly,
          immobilized_capital: immobilized,
          avg_purchase_cost: apc,
          inv_count: inv_count
        }
      end.compact
    end

    def empty_product_hash
      { units_sold: 0, revenue: 0.to_d, cogs: 0.to_d, inv_count: 0, inv_total_cost: 0.to_d }
    end

    def months_in_period
      ((end_date.to_date - start_date.to_date).to_f / 30.0).ceil.clamp(1, 12)
    end

    def worst_by(metric, products)
      filtered = products.select { |h| h[metric].present? && h[:units_sold].to_i.positive? }
      filtered.sort_by { |h| h[metric] }.first(limit)
    end

    def top_doh(products)
      products.sort_by { |h| h[:doh].infinite? ? Float::MAX : h[:doh] }
              .reverse
              .first(limit)
    end

    def top_immobilized(products)
      products.sort_by { |h| -h[:immobilized_capital].to_f }.first(limit)
    end

    def worst_scored(products)
      margins = products.pluck(:margin_pct)
      rotations = products.pluck(:rotation)
      dohs = products.pluck(:doh)
      capitals = products.map { |h| h[:immobilized_capital].to_f }

      scored = products.map do |h|
        nm = normalize(margins, h[:margin_pct])
        nr = normalize(rotations, h[:rotation])
        nd = normalize(dohs, h[:doh])
        nc = normalize(capitals, h[:immobilized_capital].to_f)

        worst_score = (weights[:margin] * (1 - nm)) +
                      (weights[:rotation] * (1 - nr)) +
                      (weights[:doh] * nd) +
                      (weights[:capital] * nc)

        h.merge(
          worst_score: worst_score.round(4),
          norm_components: { margin: nm, rotation: nr, doh: nd, capital: nc }
        )
      end

      scored.sort_by { |h| -h[:worst_score] }.first(limit)
    end

    def global_metrics(products)
      margin_vals = products.pluck(:margin_pct).compact
      rot_vals = products.pluck(:rotation).compact
      doh_vals = products.pluck(:doh).select do |v|
        v.finite?
      rescue StandardError
        false
      end

      {
        total_immobilized_capital: products.sum { |h| h[:immobilized_capital].to_f },
        avg_margin_pct: margin_vals.any? ? (margin_vals.sum / margin_vals.size).round(2) : nil,
        avg_rotation: rot_vals.any? ? (rot_vals.sum / rot_vals.size).round(2) : nil,
        avg_doh: doh_vals.any? ? (doh_vals.sum / doh_vals.size).round(1) : nil
      }
    end

    # Min-max normalization helper
    def normalize(values, value)
      vals = values.compact.map do |v|
        if begin
          v.infinite?
        rescue StandardError
          true
        end
          nil
        else
          v
        end
      end.compact
      return 0.5 if value.nil?
      return 1.0 if value.respond_to?(:infinite?) && value.infinite?
      return 0.5 if vals.empty?

      min = vals.min
      max = vals.max
      range = max - min
      return 0.5 if range <= 0

      [[(value - min) / range, 0.0].max, 1.0].min
    end
  end
end
