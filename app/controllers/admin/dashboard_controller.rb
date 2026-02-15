# frozen_string_literal: true

module Admin
  # Refactored Dashboard Controller using service objects for cleaner architecture.
  # Original controller had ~1400 lines with methods defined inside index action.
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    layout 'admin'

    # SQL constants for revenue and COGS calculations (shared across controller)
    REV_SQL = 'COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)'
    # COGS uses product's average_purchase_cost (the actual acquisition cost, not sale_order_items.unit_cost which incorrectly stores the sale price)
    COGS_SQL = 'COALESCE(products.average_purchase_cost, 0) * COALESCE(sale_order_items.quantity, 0)'
    UNITS_SQL = 'COALESCE(sale_order_items.quantity, 0)'
    PAID_STATUSES = %w[Confirmed Shipped Delivered].freeze

    # Main dashboard view with KPIs, charts, and rankings
    def index
      setup_date_filters
      setup_base_scopes
      load_kpis
      load_comparisons
      load_alerts_and_activity
      load_top_products
      load_top_users
      load_status_counts
      load_monthly_yearly_tables
      load_chart_data
      load_top_sellers_and_profitable
      load_top_inventory
      load_top_categories
      load_top_customers_reserved
      load_worst_products
      load_geo_sales
    end

    # Turbo Frame: Top Sellers by period
    def sellers
      period = params[:period].presence || 'ytd'
      scope = period_scope_for(period)
      primary_scope = scope.where(status: PAID_STATUSES)

      @rows = build_sellers_data(primary_scope)
      @rows = build_sellers_data(scope) if @rows.empty?
      @period = period

      respond_to { |format| format.html { render layout: false } }
    end

    # Turbo Frame: Most Profitable Products by period
    def profitable
      period = params[:period].presence || 'ytd'
      scope = period_scope_for(period)
      primary_scope = scope.where(status: PAID_STATUSES)

      @rows = build_profitable_data(primary_scope)
      @rows = build_profitable_data(scope) if @rows.empty?
      @period = period

      respond_to { |format| format.html { render layout: false } }
    end

    # Turbo Frame: Top Inventory by scope and metric
    def inventory_top
      @scope = params[:scope].presence || 'inv'
      @metric = params[:metric].presence || 'value'

      statuses = case @scope
                 when 'res' then %i[reserved pre_reserved pre_sold]
                 when 'all' then %i[available in_transit reserved pre_reserved pre_sold]
                 else %i[available in_transit]
                 end

      @rows = build_inventory_data(statuses, @metric)

      respond_to { |format| format.html { render layout: false } }
    end

    # Turbo Frame: Top Categories by period and metric
    def categories_rank
      period = params[:period].presence || 'ytd'
      @metric = params[:metric].presence || 'rev'
      scope = period_scope_for(period)

      @rows = build_categories_data(scope, @metric)
      @period = period

      respond_to { |format| format.html { render layout: false } }
    end

    # Turbo Frame: Top Customers by period and metric
    def customers_rank
      period = params[:period].presence || 'ytd'
      @metric = params[:metric].presence || 'sales'
      scope = period_scope_for(period)

      @rows = build_customers_data(scope, @metric)
      @period = period

      respond_to { |format| format.html { render layout: false } }
    end

    # JSON endpoint for geographic data
    def geo
      visits_by_country = VisitorLog.where.not(country: [nil, ''])
                                    .group(:country)
                                    .sum(:visit_count)
                                    .map { |c, v| { name: c, value: v.to_i } }

      visits_by_region = VisitorLog.where.not(country: [nil, ''], region: [nil, ''])
                                   .group(:country, :region)
                                   .sum(:visit_count)
                                   .map { |(c, r), v| { country: c, region: r, value: v.to_i } }

      respond_to do |format|
        format.json do
          render json: {
            visits: visits_by_country,
            visits_by_region: visits_by_region,
            sales_by_region: [],
            sales_by_country: []
          }
        end
      end
    end

    private

    # === Authorization ===
    def authorize_admin!
      redirect_to root_path, alert: 'Not authorized.' unless current_user.admin?
    end

    # === Date Filter Setup ===
    def setup_date_filters
      @now = Time.zone.now
      @range_key = params[:range].presence || 'ytd'
      @start_date, @end_date = compute_date_range(@range_key, params[:start_date], params[:end_date])
      @exclude_canceled = ActiveModel::Type::Boolean.new.cast(params.fetch(:exclude_canceled, true))
    end

    def compute_date_range(range_key, start_param, end_param)
      case range_key
      when 'last_30' then [@now.to_date - 30, @now.end_of_day]
      when 'last_90' then [@now.to_date - 90, @now.end_of_day]
      when 'this_year' then [@now.beginning_of_year.to_date, @now.end_of_day]
      when 'custom'
        s = start_param.present? ? Date.parse(start_param) : @now.beginning_of_year.to_date
        e = end_param.present? ? Time.zone.parse(end_param).end_of_day : @now.end_of_day
        [s, e]
      else
        [@now.beginning_of_year.to_date, @now.end_of_day]
      end
    rescue ArgumentError
      [@now.beginning_of_year.to_date, @now.end_of_day]
    end

    # === Base Scopes ===
    def setup_base_scopes
      @so_scope = @exclude_canceled ? SaleOrder.where.not(status: 'Canceled') : SaleOrder.all
      @po_scope = @exclude_canceled ? PurchaseOrder.where.not(status: 'Canceled') : PurchaseOrder.all
      @range = @start_date..@end_date
      @so_ytd = @so_scope.where(order_date: @range)
      @so_ytd_paid = @so_ytd.where(status: PAID_STATUSES)
      @po_ytd = @po_scope.where(order_date: @range)
    end

    def period_scope_for(period)
      now = @now || Time.zone.now
      so_scope = SaleOrder.where.not(status: 'Canceled')
      case period
      when 'ly'
        ly_start = now.beginning_of_year - 1.year
        so_scope.where(order_date: ly_start..ly_start.end_of_year)
      when 'all'
        so_scope
      else
        so_scope.where(order_date: now.beginning_of_year..now.end_of_day)
      end
    end

    # === KPI Loading ===
    def load_kpis
      rev_sql_arel = Arel.sql(REV_SQL)
      cogs_sql_arel = Arel.sql(COGS_SQL)

      @total_products = begin
        Product.active.count
      rescue StandardError
        Product.count
      end
      @total_users = User.count

      @sales_ytd = SaleOrderItem.joins(:sale_order).merge(@so_ytd).sum(rev_sql_arel).to_d
      @purchases_ytd = @po_ytd.sum(:total_cost_mxn).to_d
      @purchases_ytd = @po_ytd.sum(:total_order_cost).to_d if @purchases_ytd.zero?

      @cash_in_ytd = SaleOrderItem.joins(:sale_order).merge(@so_ytd_paid).sum(rev_sql_arel).to_d
      @cash_out_ytd = @po_ytd.sum(:total_cost_mxn).to_d
      @cash_out_ytd = @po_ytd.sum(:total_order_cost).to_d if @cash_out_ytd.zero?
      @cashflow_ytd = @cash_in_ytd - @cash_out_ytd

      @cogs_ytd = SaleOrderItem.joins(:sale_order, :product).merge(@so_ytd).sum(cogs_sql_arel).to_d
      @profit_ytd = @sales_ytd - @cogs_ytd
      @margin_ytd = @sales_ytd.positive? ? (@profit_ytd / @sales_ytd) : 0.to_d

      @orders_count_ytd = @so_ytd.count
      @po_count_ytd = @po_ytd.count
      @active_customers_ytd = @so_ytd.select(:user_id).distinct.count
      @inventory_total_value = Product.sum(:current_inventory_value).to_d

      @po_items_qty_ytd = PurchaseOrderItem.joins(:purchase_order).merge(@po_ytd).sum(:quantity).to_i
      @so_items_qty_ytd = SaleOrderItem.joins(:sale_order).merge(@so_ytd).sum(:quantity).to_i

      @purchases_total_mxn = @po_scope.sum(:total_cost_mxn).to_d
      @purchases_total_mxn = @po_scope.sum(:total_order_cost).to_d if @purchases_total_mxn.zero?

      @avg_ticket_ytd = @orders_count_ytd.positive? ? (@sales_ytd / @orders_count_ytd) : 0.to_d
      @visits_total = begin
        VisitorLog.sum(:visit_count)
      rescue StandardError
        nil
      end
      @conversion_rate_ytd = @visits_total.to_i.positive? ? (@orders_count_ytd.to_d / @visits_total.to_d) : nil

      load_customer_metrics
      load_critical_stock
      load_inventory_turnover
      load_all_time_totals
    end

    def load_customer_metrics
      first_order_by_user = @so_scope.group(:user_id).minimum(:order_date)
      @new_customers_ytd = first_order_by_user.values.count { |d| d && d >= @start_date && d <= @end_date }
      @recurring_customers_ytd = @active_customers_ytd - @new_customers_ytd
      @recurring_customers_ratio = @active_customers_ytd.positive? ? (@recurring_customers_ytd.to_d / @active_customers_ytd) : nil
    end

    def load_critical_stock
      free_counts = Inventory.free.group(:product_id).count
      rp_map = Product.where('reorder_point IS NOT NULL AND reorder_point > 0').pluck(:id, :reorder_point).to_h
      @critical_stock_count = rp_map.count { |pid, rp| free_counts.fetch(pid, 0).to_i <= rp.to_i }
    rescue StandardError
      @critical_stock_count = nil
    end

    def load_inventory_turnover
      @inventory_turnover_ytd = @inventory_total_value.positive? ? (@cogs_ytd / @inventory_total_value) : nil
    end

    def load_all_time_totals
      rev_sql_arel = Arel.sql(REV_SQL)
      @sales_total_mxn = SaleOrderItem.joins(:sale_order).merge(@so_scope).sum(rev_sql_arel).to_d
      @so_total_all_time = @so_scope.count
      @po_total_all_time = @po_scope.count
      @po_items_qty_all_time = PurchaseOrderItem.joins(:purchase_order).merge(@po_scope).sum(:quantity).to_i
      @so_items_qty_all_time = SaleOrderItem.joins(:sale_order).merge(@so_scope).sum(:quantity).to_i
    end

    # === Year-over-Year Comparisons ===
    def load_comparisons
      rev_sql_arel = Arel.sql(REV_SQL)
      cogs_sql_arel = Arel.sql(COGS_SQL)

      range_prev_start = @start_date.prev_year
      range_prev_end = @end_date.prev_year
      so_prev_range = @so_scope.where(order_date: range_prev_start..range_prev_end)
      po_prev_range = @po_scope.where(order_date: range_prev_start..range_prev_end)

      @sales_prev = SaleOrderItem.joins(:sale_order).merge(so_prev_range).sum(rev_sql_arel).to_d
      @cogs_prev = SaleOrderItem.joins(:sale_order, :product).merge(so_prev_range).sum(cogs_sql_arel).to_d
      @profit_prev = @sales_prev - @cogs_prev
      @margin_prev = @sales_prev.positive? ? (@profit_prev / @sales_prev) : 0.to_d
      @orders_prev = so_prev_range.count
      @po_count_prev = po_prev_range.count
      @active_customers_prev = so_prev_range.select(:user_id).distinct.count

      @cash_in_prev = SaleOrderItem.joins(:sale_order).merge(so_prev_range.where(status: PAID_STATUSES)).sum(rev_sql_arel).to_d
      @cash_out_prev = po_prev_range.sum(:total_cost_mxn).to_d
      @cash_out_prev = po_prev_range.sum(:total_order_cost).to_d if @cash_out_prev.zero?
      @cashflow_prev = @cash_in_prev - @cash_out_prev

      @kpi_deltas = {
        sales: pct_delta(@sales_ytd, @sales_prev),
        profit: pct_delta(@profit_ytd, @profit_prev),
        orders: pct_delta(@orders_count_ytd, @orders_prev),
        po_count: pct_delta(@po_count_ytd, @po_count_prev),
        customers: pct_delta(@active_customers_ytd, @active_customers_prev),
        margin_pp: @margin_ytd - @margin_prev,
        cashflow: pct_delta(@cashflow_ytd, @cashflow_prev)
      }
    end

    def pct_delta(curr, prev)
      prev.to_d.positive? ? ((curr.to_d - prev.to_d) / prev.to_d) : nil
    end

    # === Alerts & Recent Activity ===
    def load_alerts_and_activity
      load_alerts
      load_recent_activity
    end

    def load_alerts
      @alerts = []

      # Stock crítico
      if @critical_stock_count.to_i.positive?
        @alerts << {
          type: 'danger',
          icon: 'fa-box-open',
          message: "#{@critical_stock_count} productos con stock crítico",
          link: admin_products_path(filter: 'low_stock'),
          link_text: 'Ver productos'
        }
      end

      # Órdenes pendientes de envío
      pending_shipments = SaleOrder.where(status: 'Confirmed').count
      if pending_shipments.positive?
        @alerts << {
          type: 'warning',
          icon: 'fa-truck',
          message: "#{pending_shipments} órdenes pendientes de envío",
          link: admin_sale_orders_path(status: 'Confirmed'),
          link_text: 'Ver órdenes'
        }
      end

      # Órdenes de compra en tránsito
      in_transit_pos = PurchaseOrder.where(status: 'In Transit').count
      if in_transit_pos.positive?
        @alerts << {
          type: 'info',
          icon: 'fa-ship',
          message: "#{in_transit_pos} compras en tránsito",
          link: admin_purchase_orders_path(status: 'In Transit'),
          link_text: 'Ver compras'
        }
      end

      # Productos sin stock (agotados) - productos activos sin inventario disponible
      # Usamos subquery para evitar N+1 y contar solo productos sin inventario available
      products_with_stock = Inventory.where(status: :available).select(:product_id).distinct
      out_of_stock = begin
        Product.active.where.not(id: products_with_stock).count
      rescue StandardError
        0
      end
      if out_of_stock > 5
        @alerts << {
          type: 'warning',
          icon: 'fa-exclamation-triangle',
          message: "#{out_of_stock} productos agotados",
          link: admin_products_path(filter: 'out_of_stock'),
          link_text: 'Ver productos'
        }
      end
    rescue StandardError => e
      Rails.logger.error "Dashboard alerts error: #{e.message}"
      @alerts = []
    end

    def load_recent_activity
      # Última venta
      @last_sale = SaleOrder.where.not(status: 'Canceled').order(created_at: :desc).first

      # Última compra recibida
      @last_purchase_received = PurchaseOrder.where(status: 'Received').order(updated_at: :desc).first

      # Última compra creada
      @last_purchase_created = PurchaseOrder.order(created_at: :desc).first

      # Próximo envío (orden confirmada más antigua)
      @next_shipment = SaleOrder.where(status: 'Confirmed').order(order_date: :asc).first
    rescue StandardError => e
      Rails.logger.error "Dashboard activity error: #{e.message}"
    end

    # === Top Products Loading ===
    def load_top_products
      @top_products_all = build_top_products(@so_scope.where(status: PAID_STATUSES))

      last20_ids = @so_scope.order(order_date: :desc, created_at: :desc).limit(20).pluck(:id)
      @top_products_last20 = last20_ids.any? ? build_top_products_from_ids(last20_ids, 5) : []
    end

    def build_top_products(scope)
      SaleOrderItem.joins(:sale_order, :product)
                   .merge(scope)
                   .group('products.id', 'products.product_name', 'products.brand', 'products.category')
                   .select("products.id, products.product_name, products.brand, products.category, SUM(#{UNITS_SQL}) AS units, SUM(#{REV_SQL}) AS revenue")
                   .order('units DESC')
                   .limit(10)
                   .map { |r| format_product_row(r) }
    end

    def build_top_products_from_ids(ids, limit)
      SaleOrderItem.joins(:product)
                   .where(sale_order_id: ids)
                   .group('products.id', 'products.product_name')
                   .select("products.id, products.product_name, SUM(#{UNITS_SQL}) AS units, SUM(#{REV_SQL}) AS revenue")
                   .order('units DESC')
                   .limit(limit)
                   .map { |r| { product_id: r.id, name: r.product_name, units: r.attributes['units'].to_i, revenue: r.attributes['revenue'].to_d } }
    end

    def format_product_row(r)
      {
        product_id: r.id,
        name: r.product_name,
        brand: r.brand,
        category: r.category,
        units: r.attributes['units'].to_i,
        revenue: r.attributes['revenue'].to_d
      }
    end

    # === Top Users Loading ===
    def load_top_users
      @top_users_all = build_top_users(@so_scope)
      @top_users_range = build_top_users(@so_ytd)

      ly_start = @now.beginning_of_year - 1.year
      so_last_year = @so_scope.where(order_date: ly_start..ly_start.end_of_year)
      @top_users_last_year = build_top_users(so_last_year)

      # YTD vs previous year comparison
      range_prev_start = @start_date.prev_year
      range_prev_end = @end_date.prev_year
      so_prev_range = @so_scope.where(order_date: range_prev_start..range_prev_end)
      prev_map = build_users_map(so_prev_range)

      @top_users_ytd_vs_prev = @top_users_range.map do |u|
        prev = prev_map[u[:user_id]] || { orders_count: 0, revenue: 0.to_d }
        delta = prev[:revenue].to_d.positive? ? ((u[:revenue] - prev[:revenue]) / prev[:revenue]) : nil
        u.merge(prev_orders_count: prev[:orders_count], prev_revenue: prev[:revenue], revenue_delta_ratio: delta)
      end

      @top_orders_ytd = @so_ytd.joins(:user)
                               .select('sale_orders.id, sale_orders.total_order_value, sale_orders.order_date, sale_orders.status, users.name AS user_name')
                               .order(total_order_value: :desc)
                               .limit(5)
    end

    def build_top_users(scope)
      SaleOrderItem.joins(sale_order: :user)
                   .merge(scope)
                   .group('users.id', 'users.name')
                   .select("users.id, users.name, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{REV_SQL}) AS revenue")
                   .order('revenue DESC')
                   .limit(10)
                   .map { |r| format_user_row(r) }
    end

    def build_users_map(scope)
      SaleOrderItem.joins(sale_order: :user)
                   .merge(scope)
                   .group('users.id')
                   .select("users.id, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{REV_SQL}) AS revenue")
                   .index_by(&:id)
                   .transform_values { |r| { orders_count: r.attributes['orders_count'].to_i, revenue: r.attributes['revenue'].to_d } }
    end

    def format_user_row(r)
      {
        user_id: r.id,
        name: r.name.presence || r.id,
        orders_count: r.attributes['orders_count'].to_i,
        revenue: r.attributes['revenue'].to_d
      }
    end

    # === Status Counts ===
    def load_status_counts
      @so_status_counts = @so_scope.group(:status).count
      @po_status_counts = @po_scope.group(:status).count
      @so_total_ytd = @sales_ytd
      @po_total_ytd = @purchases_ytd
      @so_avg_ticket_ytd = @so_ytd.average(:total_order_value)&.to_d || 0.to_d
      @po_avg_ticket_ytd = @po_ytd.average(:total_cost_mxn)&.to_d || @po_ytd.average(:total_order_cost)&.to_d || 0.to_d

      # Pie chart data for order status donut charts
      so_colors = { 'Draft' => '#94a3b8', 'Reserved' => '#f59e0b', 'Confirmed' => '#3b82f6',
                    'Preparing' => '#8b5cf6', 'Shipped' => '#06b6d4', 'Delivered' => '#10b981',
                    'Canceled' => '#ef4444' }
      @so_status_pie = @so_status_counts.map { |s, c| { name: s, value: c, itemStyle: { color: so_colors[s] || '#64748b' } } }

      po_colors = { 'Draft' => '#94a3b8', 'Confirmed' => '#3b82f6', 'In Transit' => '#f59e0b',
                    'Received' => '#10b981', 'Canceled' => '#ef4444' }
      @po_status_pie = @po_status_counts.map { |s, c| { name: s, value: c, itemStyle: { color: po_colors[s] || '#64748b' } } }
    end

    # === Monthly/Yearly Tables ===
    def load_monthly_yearly_tables
      load_monthly_current_year
      load_annual_stats
    end

    def load_monthly_current_year
      so_month_key = month_group_expr('sale_orders', 'order_date')
      po_month_key = month_group_expr('purchase_orders', 'order_date')
      cogs_sql_arel = Arel.sql(COGS_SQL)

      sales_monthly = @so_ytd.group(Arel.sql(so_month_key)).sum(:total_order_value)
      cogs_monthly = SaleOrderItem.joins(:sale_order, :product).merge(@so_ytd).group(Arel.sql(so_month_key)).sum(cogs_sql_arel)
      purchases_monthly = @po_ytd.group(Arel.sql(po_month_key)).sum(:total_cost_mxn)

      sales_m_map = sales_monthly.transform_keys { |k| extract_month_index(k) }
      cogs_m_map = cogs_monthly.transform_keys { |k| extract_month_index(k) }
      purchases_m_map = purchases_monthly.transform_keys { |k| extract_month_index(k) }

      @monthly_current_year = (1..12).map do |m|
        sales = (sales_m_map[m] || 0).to_d
        cogs = (cogs_m_map[m] || 0).to_d
        buys = (purchases_m_map[m] || 0).to_d
        profit = sales - cogs
        margin = sales.positive? ? (profit / sales) : 0.to_d
        { month: Date::MONTHNAMES[m], sales: sales, purchases: buys, cogs: cogs, profit: profit, margin: margin }
      end
    end

    def load_annual_stats
      years = ((@now.year - 4)..@now.year).to_a
      so_5y = @so_scope.where(order_date: (@now.beginning_of_year - 4.years)..@now.end_of_year)
      po_5y = @po_scope.where(order_date: (@now.beginning_of_year - 4.years)..@now.end_of_year)

      so_year_key = year_group_expr('sale_orders', 'order_date')
      po_year_key = year_group_expr('purchase_orders', 'order_date')
      cogs_sql_arel = Arel.sql(COGS_SQL)

      sales_yearly = so_5y.group(Arel.sql(so_year_key)).sum(:total_order_value)
      cogs_yearly = SaleOrderItem.joins(:sale_order, :product).merge(so_5y).group(Arel.sql(so_year_key)).sum(cogs_sql_arel)
      purchases_yearly = po_5y.group(Arel.sql(po_year_key)).sum(:total_cost_mxn)

      sales_y_map = sales_yearly.transform_keys { |k| extract_year_index(k) }
      cogs_y_map = cogs_yearly.transform_keys { |k| extract_year_index(k) }
      purchases_y_map = purchases_yearly.transform_keys { |k| extract_year_index(k) }

      @annual_stats = years.map do |y|
        sales = (sales_y_map[y] || 0).to_d
        cogs = (cogs_y_map[y] || 0).to_d
        buys = (purchases_y_map[y] || 0).to_d
        profit = sales - cogs
        margin = sales.positive? ? (profit / sales) : 0.to_d
        { year: y, sales: sales, purchases: buys, cogs: cogs, profit: profit, margin: margin }
      end
    end

    # === Chart Data ===
    def load_chart_data
      trend_start = (@end_date - 11.months).beginning_of_month
      trend_range = trend_start..@end_date
      month_key_expr = month_group_expr('sale_orders', 'order_date')
      rev_sql_arel = Arel.sql(REV_SQL)
      cogs_sql_arel = Arel.sql(COGS_SQL)

      trend_rev = SaleOrderItem.joins(:sale_order)
                               .merge(@so_scope.where(order_date: trend_range))
                               .group(Arel.sql(month_key_expr))
                               .sum(rev_sql_arel)
      trend_cogs = SaleOrderItem.joins(:sale_order, :product)
                                .merge(@so_scope.where(order_date: trend_range))
                                .group(Arel.sql(month_key_expr))
                                .sum(cogs_sql_arel)

      trend_rev_map = trend_rev.transform_keys { |k| normalize_month_key(k) }
      trend_cogs_map = trend_cogs.transform_keys { |k| normalize_month_key(k) }
      months_keys = (0..11).map { |i| (trend_start + i.months).strftime('%Y-%m') }

      @chart_sales_trend = {
        months: months_keys,
        revenue: months_keys.map { |k| (trend_rev_map[k] || 0).to_d },
        cogs: months_keys.map { |k| (trend_cogs_map[k] || 0).to_d }
      }
      @chart_sales_trend[:profit] = months_keys.each_index.map do |i|
        @chart_sales_trend[:revenue][i] - @chart_sales_trend[:cogs][i]
      end

      load_cashflow_chart(trend_start, trend_range, months_keys, month_key_expr)
      load_cashflow_comparison_chart
      load_category_charts
    end

    def load_cashflow_chart(_trend_start, trend_range, months_keys, month_key_expr)
      month_key_expr_po = month_group_expr('purchase_orders', 'order_date')
      rev_sql_arel = Arel.sql(REV_SQL)

      inflow_map = SaleOrderItem.joins(:sale_order)
                                .merge(@so_scope.where(order_date: trend_range, status: PAID_STATUSES))
                                .group(Arel.sql(month_key_expr))
                                .sum(rev_sql_arel)

      outflow_po_costs = @po_scope.where(order_date: trend_range)
      outflow_map = outflow_po_costs.group(Arel.sql(month_key_expr_po)).sum(:total_cost_mxn)
      outflow_map = outflow_po_costs.group(Arel.sql(month_key_expr_po)).sum(:total_order_cost) if outflow_map.values.all? { |v| v.to_d.zero? }

      inflow_norm = inflow_map.transform_keys { |k| normalize_month_key(k) }
      outflow_norm = outflow_map.transform_keys { |k| normalize_month_key(k) }

      @chart_cashflow = {
        months: months_keys,
        inflow: months_keys.map { |k| (inflow_norm[k] || 0).to_d },
        outflow: months_keys.map { |k| (outflow_norm[k] || 0).to_d }
      }
      @chart_cashflow[:net] = months_keys.each_index.map do |i|
        @chart_cashflow[:inflow][i] - @chart_cashflow[:outflow][i]
      end
    end

    # Comparativo de flujo de caja: año actual vs año anterior (mes a mes)
    def load_cashflow_comparison_chart
      current_year = @now.year
      prev_year = current_year - 1
      month_labels = %w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic]

      month_key_expr_so = month_group_expr('sale_orders', 'order_date')
      month_key_expr_po = month_group_expr('purchase_orders', 'order_date')
      rev_sql_arel = Arel.sql(REV_SQL)

      # Ingresos (ventas pagadas) por mes - año actual
      current_year_start = Date.new(current_year, 1, 1)
      current_year_end = Date.new(current_year, 12, 31).end_of_day
      inflow_current = SaleOrderItem.joins(:sale_order)
                                    .merge(@so_scope.where(order_date: current_year_start..current_year_end, status: PAID_STATUSES))
                                    .group(Arel.sql(month_key_expr_so))
                                    .sum(rev_sql_arel)
                                    .transform_keys { |k| normalize_month_key(k) }

      # Egresos (compras) por mes - año actual
      outflow_current_scope = @po_scope.where(order_date: current_year_start..current_year_end)
      outflow_current = outflow_current_scope.group(Arel.sql(month_key_expr_po)).sum(:total_cost_mxn)
      outflow_current = outflow_current_scope.group(Arel.sql(month_key_expr_po)).sum(:total_order_cost) if outflow_current.values.all? { |v| v.to_d.zero? }
      outflow_current = outflow_current.transform_keys { |k| normalize_month_key(k) }

      # Ingresos (ventas pagadas) por mes - año anterior
      prev_year_start = Date.new(prev_year, 1, 1)
      prev_year_end = Date.new(prev_year, 12, 31).end_of_day
      inflow_prev = SaleOrderItem.joins(:sale_order)
                                 .merge(@so_scope.where(order_date: prev_year_start..prev_year_end, status: PAID_STATUSES))
                                 .group(Arel.sql(month_key_expr_so))
                                 .sum(rev_sql_arel)
                                 .transform_keys { |k| normalize_month_key(k) }

      # Egresos (compras) por mes - año anterior
      outflow_prev_scope = @po_scope.where(order_date: prev_year_start..prev_year_end)
      outflow_prev = outflow_prev_scope.group(Arel.sql(month_key_expr_po)).sum(:total_cost_mxn)
      outflow_prev = outflow_prev_scope.group(Arel.sql(month_key_expr_po)).sum(:total_order_cost) if outflow_prev.values.all? { |v| v.to_d.zero? }
      outflow_prev = outflow_prev.transform_keys { |k| normalize_month_key(k) }

      # Generar keys por mes para cada año
      current_months = (1..12).map { |m| format('%04d-%02d', current_year, m) }
      prev_months = (1..12).map { |m| format('%04d-%02d', prev_year, m) }

      # Calcular flujo neto (ingresos - egresos) por mes
      net_current = current_months.map { |k| (inflow_current[k] || 0).to_d - (outflow_current[k] || 0).to_d }
      net_prev = prev_months.map { |k| (inflow_prev[k] || 0).to_d - (outflow_prev[k] || 0).to_d }

      @chart_cashflow_comparison = {
        months: month_labels,
        current_year: current_year,
        prev_year: prev_year,
        net_current: net_current,
        net_prev: net_prev,
        inflow_current: current_months.map { |k| (inflow_current[k] || 0).to_d },
        outflow_current: current_months.map { |k| (outflow_current[k] || 0).to_d },
        inflow_prev: prev_months.map { |k| (inflow_prev[k] || 0).to_d },
        outflow_prev: prev_months.map { |k| (outflow_prev[k] || 0).to_d }
      }
    end

    def load_category_charts
      rev_sql_arel = Arel.sql(REV_SQL)
      cogs_sql_arel = Arel.sql(COGS_SQL)
      month_key_expr = month_group_expr('sale_orders', 'order_date')

      # Monthly stacked by category (YTD selection)
      by_month_cat = SaleOrderItem.joins(:sale_order, :product)
                                  .merge(@so_ytd)
                                  .group(Arel.sql(month_key_expr), 'products.category')
                                  .sum(rev_sql_arel)

      by_month_cat_norm = by_month_cat.transform_keys do |(mk, cat)|
        [normalize_month_key(mk), cat.presence || 'Uncategorized']
      end

      months_ytd_keys = months_between(@start_date.beginning_of_month, @end_date.end_of_month)

      # Top categories across YTD
      cats_totals = Hash.new(0.to_d)
      by_month_cat_norm.each { |((_mk, cat)), val| cats_totals[cat] += val.to_d }
      top_cats = cats_totals.sort_by { |(_, v)| -v }.first(5).map(&:first)
      other_cats = cats_totals.keys - top_cats

      series = top_cats.map do |cat|
        { name: cat, data: months_ytd_keys.map { |mk| (by_month_cat_norm[[mk, cat]] || 0).to_d } }
      end
      series << { name: 'Others', data: months_ytd_keys.map { |mk| other_cats.sum { |c| (by_month_cat_norm[[mk, c]] || 0).to_d } } } if other_cats.any?
      @chart_monthly_by_category = { months: months_ytd_keys, series: series }

      # Brand profitability
      by_brand_rev = SaleOrderItem.joins(:sale_order, :product).merge(@so_ytd).group('products.brand').sum(rev_sql_arel)
      by_brand_cogs = SaleOrderItem.joins(:sale_order, :product).merge(@so_ytd).group('products.brand').sum(cogs_sql_arel)
      brands = (by_brand_rev.keys + by_brand_cogs.keys).uniq
      brand_profit = brands.map { |b| [b.presence || 'Unbranded', by_brand_rev[b].to_d - by_brand_cogs[b].to_d] }
      brand_profit.sort_by! { |(_, p)| -p }
      top_brands = brand_profit.first(8)
      @chart_brand_profit = { brands: top_brands.map(&:first), profit: top_brands.map { |(_, p)| p } }

      # Category profitability
      by_cat_rev = SaleOrderItem.joins(:sale_order, :product).merge(@so_ytd).group('products.category').sum(rev_sql_arel)
      by_cat_cogs = SaleOrderItem.joins(:sale_order, :product).merge(@so_ytd).group('products.category').sum(cogs_sql_arel)
      cats = (by_cat_rev.keys + by_cat_cogs.keys).uniq
      cat_profit = cats.map { |c| [c.presence || 'Uncategorized', by_cat_rev[c].to_d - by_cat_cogs[c].to_d] }
      cat_profit.sort_by! { |(_, p)| -p }
      top_cats_profit = cat_profit.first(8)
      @chart_category_profit = { categories: top_cats_profit.map(&:first), profit: top_cats_profit.map { |(_, p)| p } }
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

    # === Top Sellers and Profitable (for index page tabs) ===
    def load_top_sellers_and_profitable
      @top_sellers_ytd = build_sellers_data(@so_ytd_paid)
      @top_sellers_ytd = build_sellers_data(@so_ytd) if @top_sellers_ytd.empty?

      ly_start = @now.beginning_of_year - 1.year
      so_last_year_paid = @so_scope.where(order_date: ly_start..ly_start.end_of_year, status: PAID_STATUSES)
      @top_sellers_last_year = build_sellers_data(so_last_year_paid)

      @top_products_profit_ytd = build_profitable_products(@so_ytd_paid, @range)
      @top_products_profit_last_year = build_profitable_products(
        @so_scope.where(order_date: ly_start..ly_start.end_of_year, status: PAID_STATUSES),
        ly_start..ly_start.end_of_year
      )
      @top_products_profit_all_time = build_profitable_products(@so_scope.where(status: PAID_STATUSES), nil)
    end

    def build_sellers_data(scope)
      SaleOrderItem.joins(:sale_order, :product)
                   .merge(scope)
                   .group('products.id', 'products.product_name', 'products.brand', 'products.category')
                   .select("products.id, products.product_name, products.brand, products.category, SUM(#{UNITS_SQL}) AS units, SUM(#{REV_SQL}) AS revenue")
                   .order('units DESC')
                   .limit(10)
                   .map { |r| format_product_row(r) }
    end

    def build_profitable_data(scope)
      SaleOrderItem.joins(:sale_order, :product)
                   .merge(scope)
                   .group('products.id', 'products.product_name', 'products.brand', 'products.category')
                   .select("products.id AS product_id, products.product_name, products.brand, products.category, SUM(#{REV_SQL}) AS revenue, SUM(#{COGS_SQL}) AS cogs, SUM(#{REV_SQL}) - SUM(#{COGS_SQL}) AS profit")
                   .order('profit DESC')
                   .limit(10)
                   .map do |r|
                     {
                       product_id: r.attributes['product_id'].to_i,
                       name: r.product_name,
                       brand: r.brand,
                       category: r.category,
                       revenue: r.attributes['revenue'].to_d,
                       cogs: r.attributes['cogs'].to_d,
                       profit: r.attributes['profit'].to_d
                     }
                   end
    end

    def build_profitable_products(scope, date_range)
      sales_rows = SaleOrderItem.joins(:sale_order, :product)
                                .merge(scope)
                                .group('products.id', 'products.product_name', 'products.brand', 'products.category')
                                .select("products.id AS product_id, products.product_name, products.brand, products.category, SUM(#{REV_SQL}) AS sales_total")

      waste_scope = Inventory.joins(:product).where(status: %i[marketing damaged lost scrap])
      waste_scope = waste_scope.where(status_changed_at: date_range) if date_range
      waste_rows = waste_scope.group('products.id').select('products.id AS product_id, SUM(inventories.purchase_cost) AS waste_total')
      waste_map = waste_rows.index_by { |r| r.attributes['product_id'].to_i }

      cogs_rows_inv = Inventory.joins(:product, :sale_order)
                               .merge(scope)
                               .where(status: :sold)
                               .group('products.id')
                               .select('products.id AS product_id, SUM(inventories.purchase_cost) AS cogs_total')

      cogs_rows = if cogs_rows_inv.any?
                    cogs_rows_inv
                  else
                    SaleOrderItem.joins(:sale_order, :product)
                                 .merge(scope)
                                 .group('products.id')
                                 .select("products.id AS product_id, SUM(#{COGS_SQL}) AS cogs_total")
                  end

      sales_map = sales_rows.index_by { |r| r.attributes['product_id'].to_i }
      cogs_map = cogs_rows.index_by { |r| r.attributes['product_id'].to_i }
      all_ids = (sales_map.keys + cogs_map.keys + waste_map.keys).uniq

      all_ids.map do |pid|
        srow = sales_map[pid]
        sales = srow&.attributes&.dig('sales_total').to_d
        cogs = cogs_map[pid]&.attributes&.dig('cogs_total').to_d
        waste = waste_map[pid]&.attributes&.dig('waste_total').to_d
        {
          product_id: pid,
          name: srow&.product_name,
          brand: srow&.brand,
          category: srow&.category.presence || 'Uncategorized',
          revenue: sales,
          cogs: cogs,
          profit: sales - cogs - waste
        }
      end.sort_by { |h| -h[:profit] }.first(10)
    end

    # === Top Inventory ===
    def load_top_inventory
      inv_statuses = %i[available in_transit]
      reserved_statuses = %i[reserved pre_reserved pre_sold]
      all_statuses = inv_statuses + reserved_statuses

      @top_inventory_by_value_inventory, @top_inventory_by_quantity_inventory = build_inventory_sets(inv_statuses)
      @top_inventory_by_value_reserved, @top_inventory_by_quantity_reserved = build_inventory_sets(reserved_statuses)
      @top_inventory_by_value_all, @top_inventory_by_quantity_all = build_inventory_sets(all_statuses)

      @top_inventory_by_value = @top_inventory_by_value_all
      @top_inventory_by_quantity = @top_inventory_by_quantity_all
    end

    def build_inventory_sets(statuses)
      base = Inventory.joins(:product)
                      .where(status: statuses)
                      .group('products.id', 'products.product_name', 'products.brand', 'products.category')

      by_value = base.select('products.id, products.product_name, products.brand, products.category, SUM(inventories.purchase_cost) AS inventory_value')
                     .order('inventory_value DESC')
                     .limit(10)
                     .map { |r| format_inventory_row(r) }

      by_qty = base.select('products.id, products.product_name, products.brand, products.category, COUNT(inventories.id) AS units_count, SUM(inventories.purchase_cost) AS inventory_value')
                   .order('units_count DESC')
                   .limit(10)
                   .map do |r|
        format_inventory_row(r, include_qty: true)
      end

      [by_value, by_qty]
    end

    def build_inventory_data(statuses, metric)
      base = Inventory.joins(:product)
                      .where(status: statuses)
                      .group('products.id', 'products.product_name', 'products.brand', 'products.category')

      rel = if metric == 'qty'
              base.select('products.id, products.product_name, products.brand, products.category, COUNT(inventories.id) AS units_count, SUM(inventories.purchase_cost) AS inventory_value')
                  .order('units_count DESC')
            else
              base.select('products.id, products.product_name, products.brand, products.category, SUM(inventories.purchase_cost) AS inventory_value')
                  .order('inventory_value DESC')
            end

      rel.limit(10).map { |r| format_inventory_row(r, include_qty: metric == 'qty') }
    end

    def format_inventory_row(r, include_qty: false)
      row = {
        product_id: r.id,
        name: r.product_name,
        brand: r.brand,
        category: r.category,
        inventory_value: r.attributes['inventory_value'].to_d
      }
      row[:units_count] = r.attributes['units_count'].to_i if include_qty
      row
    end

    # === Top Categories ===
    def load_top_categories
      @top_categories_ytd = build_categories_data(@so_ytd, 'rev')
      @top_categories_profit_ytd = build_categories_data(@so_ytd, 'profit')

      ly_start = @now.beginning_of_year - 1.year
      so_prev = @so_scope.where(order_date: ly_start..ly_start.end_of_year)
      @top_categories_last_year = build_categories_data(so_prev, 'rev')
      @top_categories_profit_last_year = build_categories_data(so_prev, 'profit')

      @top_categories_all_time = build_categories_data(@so_scope, 'rev')
      @top_categories_profit_all_time = build_categories_data(@so_scope, 'profit')
    end

    def build_categories_data(scope, metric)
      rev_sql_arel = Arel.sql(REV_SQL)
      cogs_sql_arel = Arel.sql(COGS_SQL)

      by_cat_rev = SaleOrderItem.joins(:sale_order, :product)
                                .merge(scope)
                                .group('products.category')
                                .sum(rev_sql_arel)

      if metric == 'profit'
        by_cat_cogs = SaleOrderItem.joins(:sale_order, :product)
                                   .merge(scope)
                                   .group('products.category')
                                   .sum(cogs_sql_arel)
        cats = (by_cat_rev.keys + by_cat_cogs.keys).uniq
        cats.map do |cat|
          rev = by_cat_rev[cat].to_d
          cogs = by_cat_cogs[cat].to_d
          { category: cat.presence || 'Uncategorized', value: rev - cogs, profit: rev - cogs }
        end.sort_by { |h| -h[:value] }.first(10)
      else
        by_cat_rev.map { |cat, val| { category: cat.presence || 'Uncategorized', value: val.to_d, revenue: val.to_d } }
                  .sort_by { |h| -h[:value] }
                  .first(10)
      end
    end

    # === Top Customers Reserved ===
    def load_top_customers_reserved
      reserved_statuses = %i[reserved pre_reserved pre_sold]
      ly_start = @now.beginning_of_year - 1.year
      so_last_year = @so_scope.where(order_date: ly_start..ly_start.end_of_year)

      @top_users_reserved_ytd = build_reserved_users(@so_ytd, reserved_statuses)
      @top_users_reserved_last_year = build_reserved_users(so_last_year, reserved_statuses)
      @top_users_reserved_all = build_reserved_users(@so_scope, reserved_statuses)

      @top_users_sales_reserved_ytd = combine_sales_reserved(@top_users_range, @top_users_reserved_ytd)
      @top_users_sales_reserved_last_year = combine_sales_reserved(@top_users_last_year, @top_users_reserved_last_year)
      @top_users_sales_reserved_all = combine_sales_reserved(@top_users_all, @top_users_reserved_all)
    end

    def build_reserved_users(scope, statuses)
      Inventory.joins(sale_order: :user)
               .merge(scope)
               .where(status: statuses)
               .group('users.id', 'users.name')
               .select('users.id, users.name, COUNT(inventories.id) AS units_reserved, SUM(inventories.purchase_cost) AS reserved_value')
               .order('reserved_value DESC')
               .limit(10)
               .map do |r|
        { user_id: r.id, name: r.name.presence || r.id, units_reserved: r.attributes['units_reserved'].to_i,
          reserved_value: r.attributes['reserved_value'].to_d }
      end
    end

    def combine_sales_reserved(sales_rows, reserved_rows)
      s_map = (sales_rows || []).index_by { |r| r[:user_id] }
      r_map = (reserved_rows || []).index_by { |r| r[:user_id] }

      (s_map.keys + r_map.keys).uniq.map do |uid|
        s = s_map[uid]
        r = r_map[uid]
        name = s&.dig(:name).presence || r&.dig(:name).presence || uid
        orders = s ? s[:orders_count].to_i : 0
        revenue = s ? s[:revenue].to_d : 0.to_d
        units_reserved = r ? r[:units_reserved].to_i : 0
        reserved_value = r ? r[:reserved_value].to_d : 0.to_d
        total = revenue + reserved_value
        { user_id: uid, name: name, orders_count: orders, revenue: revenue, units_reserved: units_reserved, reserved_value: reserved_value, total: total }
      end.sort_by { |h| -h[:total] }.first(10)
    end

    def build_customers_data(scope, metric)
      reserved_statuses = %i[reserved pre_reserved pre_sold]

      sales_rows = SaleOrderItem.joins(sale_order: :user)
                                .merge(scope.where(status: PAID_STATUSES))
                                .group('users.id', 'users.name')
                                .select("users.id AS user_id, users.name, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{REV_SQL}) AS revenue")
                                .map do |r|
        { user_id: r.attributes['user_id'].to_i, name: r.name.presence || r.attributes['user_id'],
          orders_count: r.attributes['orders_count'].to_i, revenue: r.attributes['revenue'].to_d }
      end

      reserved_rows = Inventory.joins(sale_order: :user)
                               .merge(scope)
                               .where(status: reserved_statuses)
                               .group('users.id', 'users.name')
                               .select('users.id AS user_id, users.name, COUNT(inventories.id) AS units_reserved, SUM(inventories.purchase_cost) AS reserved_value')
                               .map do |r|
        { user_id: r.attributes['user_id'].to_i, name: r.name.presence || r.attributes['user_id'],
          units_reserved: r.attributes['units_reserved'].to_i, reserved_value: r.attributes['reserved_value'].to_d }
      end

      case metric
      when 'reserved'
        reserved_rows.sort_by { |h| -h[:reserved_value] }.first(10)
      when 'combined'
        combine_sales_reserved(sales_rows, reserved_rows)
      else
        sales_rows.sort_by { |h| -h[:revenue] }.first(10)
      end
    end

    # === Worst Products ===
    def load_worst_products
      builder = ::Dashboard::WorstProductsBuilder.new(
        start_date: @start_date,
        end_date: @end_date,
        weights: { w1: params[:w1], w2: params[:w2], w3: params[:w3], w4: params[:w4] },
        limit: 10,
        time_reference: @now
      )

      result = builder.call
      @worst_margin_products = result[:worst_margin]
      @worst_rotation_products = result[:worst_rotation]
      @top_doh_products = result[:top_doh]
      @top_immobilized_products = result[:top_immobilized]
      @worst_score_products = result[:worst_score]

      global = result[:global_metrics]
      @worst_global_total_immobilized_capital = global[:total_immobilized_capital]
      @worst_global_avg_margin_pct = global[:avg_margin_pct]
      @worst_global_avg_rotation = global[:avg_rotation]
      @worst_global_avg_doh = global[:avg_doh]
    end

    # === Geographic Sales ===
    def load_geo_sales
      builder = ::Dashboard::GeoSalesBuilder.new(time_reference: @now)
      result = builder.call

      @sales_by_country_ytd = result[:ytd][:countries]
      @sales_by_mexico_states_ytd = result[:ytd][:mexico_states]
      @sales_by_country_last_year = result[:last_year][:countries]
      @sales_by_mexico_states_last_year = result[:last_year][:mexico_states]
      @sales_by_country_all_time = result[:all_time][:countries]
      @sales_by_mexico_states_all_time = result[:all_time][:mexico_states]

      # Backward compatibility
      @sales_by_country = @sales_by_country_ytd
      @sales_by_mexico_states = @sales_by_mexico_states_ytd
    end

    # === Database Adapter Helpers ===
    def db_adapter
      @db_adapter ||= ActiveRecord::Base.connection.adapter_name.to_s.downcase
    end

    def month_group_expr(table, column)
      col = "#{table}.#{column}"
      db_adapter.include?('sqlite') ? "strftime('%Y-%m-01', #{col})" : "DATE_TRUNC('month', #{col})"
    end

    def year_group_expr(table, column)
      col = "#{table}.#{column}"
      db_adapter.include?('sqlite') ? "strftime('%Y', #{col})" : "DATE_TRUNC('year', #{col})"
    end

    def extract_month_index(key)
      return key.month if key.respond_to?(:month)

      Date.parse(key).month if key.is_a?(String)
    rescue ArgumentError
      nil
    end

    def extract_year_index(key)
      return key.year if key.respond_to?(:year)

      key.to_s[0, 4].to_i if key.is_a?(String)
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
  end
end
