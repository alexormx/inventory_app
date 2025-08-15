class Admin::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  layout "admin"

  def index
  # Filtros
  now        = Time.zone.now
  @range_key = params[:range].presence || 'ytd'
  @start_date, @end_date = compute_date_range(@range_key, params[:start_date], params[:end_date], now)
  @exclude_canceled = ActiveModel::Type::Boolean.new.cast(params.fetch(:exclude_canceled, true))

  # Scopes base
  so_scope = @exclude_canceled ? SaleOrder.where.not(status: "Canceled") : SaleOrder.all
  po_scope = @exclude_canceled ? PurchaseOrder.where.not(status: "Canceled") : PurchaseOrder.all

  range = @start_date..@end_date
  so_ytd = so_scope.where(order_date: range)
  po_ytd = po_scope.where(order_date: range)

    # KPIs básicos
    @total_products = Product.active.count rescue Product.count
    @total_users    = User.count

    # Ventas/Compras YTD
    @sales_ytd     = so_ytd.sum(:total_order_value).to_d
    @purchases_ytd = po_ytd.sum(:total_cost_mxn).to_d
    if @purchases_ytd.zero?
      # Fallback si total_cost_mxn no se usa
      @purchases_ytd = po_ytd.sum(:total_order_cost).to_d
    end

    # COGS YTD (costo de lo vendido)
    cogs_sql = Arel.sql("COALESCE(sale_order_items.unit_cost, 0) * COALESCE(sale_order_items.quantity, 0)")
    @cogs_ytd = SaleOrderItem.joins(:sale_order)
                             .merge(so_ytd)
                             .sum(cogs_sql).to_d

    @profit_ytd = @sales_ytd - @cogs_ytd
    @margin_ytd = @sales_ytd.positive? ? (@profit_ytd / @sales_ytd) : 0.to_d

    # Top 10 productos históricos (por unidades)
    rev_sql = "COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)"
    top_products = SaleOrderItem.joins(:sale_order, :product)
                                .merge(so_scope)
                                .group("products.id", "products.product_name")
                                .select("products.id, products.product_name, SUM(sale_order_items.quantity) AS units, SUM(#{rev_sql}) AS revenue")
                                .order("units DESC")
                                .limit(10)
    @top_products_all = top_products.map { |r| { product_id: r.id, name: r.product_name, units: r.attributes["units"].to_i, revenue: r.attributes["revenue"].to_d } }

    # Top 5 productos en las últimas 20 ventas
    last20_ids = so_scope.order(order_date: :desc, created_at: :desc).limit(20).pluck(:id)
    if last20_ids.any?
      top_last20 = SaleOrderItem.joins(:product)
                                 .where(sale_order_id: last20_ids)
                                 .group("products.id", "products.product_name")
                                 .select("products.id, products.product_name, SUM(sale_order_items.quantity) AS units, SUM(#{rev_sql}) AS revenue")
                                 .order("units DESC")
                                 .limit(5)
      @top_products_last20 = top_last20.map { |r| { product_id: r.id, name: r.product_name, units: r.attributes["units"].to_i, revenue: r.attributes["revenue"].to_d } }
    else
      @top_products_last20 = []
    end

    # Top 5 usuarios con mayores compras históricas (por ingresos)
    users_top = so_scope.joins(:user)
                        .group("users.id", "users.name")
                        .select("users.id, users.name, COUNT(*) AS orders_count, SUM(total_order_value) AS revenue, AVG(total_order_value) AS avg_ticket")
                        .order("revenue DESC")
                        .limit(5)
    @top_users_all = users_top.map { |r| { user_id: r.id, name: r.name.presence || r.id, orders_count: r.attributes["orders_count"].to_i, revenue: r.attributes["revenue"].to_d, avg_ticket: r.attributes["avg_ticket"].to_d } }

  # Top 5 users within current range
  users_top_range = so_ytd.joins(:user)
              .group("users.id", "users.name")
              .select("users.id, users.name, COUNT(*) AS orders_count, SUM(total_order_value) AS revenue, AVG(total_order_value) AS avg_ticket")
              .order("revenue DESC")
              .limit(5)
  @top_users_range = users_top_range.map { |r| { user_id: r.id, name: r.name.presence || r.id, orders_count: r.attributes["orders_count"].to_i, revenue: r.attributes["revenue"].to_d, avg_ticket: r.attributes["avg_ticket"].to_d } }

    # Top 5 mayores compras del año actual (órdenes de venta por monto)
    @top_orders_ytd = so_ytd.joins(:user)
                            .select("sale_orders.id, sale_orders.total_order_value, sale_orders.order_date, sale_orders.status, users.name AS user_name")
                            .order(total_order_value: :desc)
                            .limit(5)

    # Estadísticas generales
    @so_status_counts = so_scope.group(:status).count
    @po_status_counts = po_scope.group(:status).count
    @so_total_ytd     = @sales_ytd
    @po_total_ytd     = @purchases_ytd
    @so_avg_ticket_ytd = so_ytd.average(:total_order_value)&.to_d || 0.to_d
    @po_avg_ticket_ytd = po_ytd.average(:total_cost_mxn)&.to_d || po_ytd.average(:total_order_cost)&.to_d || 0.to_d

  # Tabla mensual del año en curso (adapter-aware)
  so_month_key = month_group_expr('sale_orders', 'order_date')
  po_month_key = month_group_expr('purchase_orders', 'order_date')

  sales_monthly = so_ytd.group(Arel.sql(so_month_key)).sum(:total_order_value)
  cogs_monthly  = SaleOrderItem.joins(:sale_order)
                 .merge(so_ytd)
                 .group(Arel.sql(so_month_key))
                 .sum(cogs_sql)
  purchases_monthly = po_ytd.group(Arel.sql(po_month_key)).sum(:total_cost_mxn)

  sales_m_map     = sales_monthly.transform_keys { |k| extract_month_index(k) }
  cogs_m_map      = cogs_monthly.transform_keys { |k| extract_month_index(k) }
  purchases_m_map = purchases_monthly.transform_keys { |k| extract_month_index(k) }

    @monthly_current_year = (1..12).map do |m|
      sales = (sales_m_map[m] || 0).to_d
      cogs  = (cogs_m_map[m] || 0).to_d
      buys  = (purchases_m_map[m] || 0).to_d
      profit = sales - cogs
      margin = sales.positive? ? (profit / sales) : 0.to_d
      {
        month: Date::MONTHNAMES[m],
        sales: sales,
        purchases: buys,
        cogs: cogs,
        profit: profit,
        margin: margin
      }
    end

  # Tabla anual (últimos 5 años) (adapter-aware)
    years = ((now.year - 4)..now.year).to_a
    so_5y = so_scope.where(order_date: (now.beginning_of_year - 4.years)..now.end_of_year)
    po_5y = po_scope.where(order_date: (now.beginning_of_year - 4.years)..now.end_of_year)

  so_year_key = year_group_expr('sale_orders', 'order_date')
  po_year_key = year_group_expr('purchase_orders', 'order_date')

  sales_yearly = so_5y.group(Arel.sql(so_year_key)).sum(:total_order_value)
  cogs_yearly  = SaleOrderItem.joins(:sale_order)
                .merge(so_5y)
                .group(Arel.sql(so_year_key))
                .sum(cogs_sql)
  purchases_yearly = po_5y.group(Arel.sql(po_year_key)).sum(:total_cost_mxn)

  sales_y_map     = sales_yearly.transform_keys { |k| extract_year_index(k) }
  cogs_y_map      = cogs_yearly.transform_keys { |k| extract_year_index(k) }
  purchases_y_map = purchases_yearly.transform_keys { |k| extract_year_index(k) }

    @annual_stats = years.map do |y|
      sales = (sales_y_map[y] || 0).to_d
      cogs  = (cogs_y_map[y] || 0).to_d
      buys  = (purchases_y_map[y] || 0).to_d
      profit = sales - cogs
      margin = sales.positive? ? (profit / sales) : 0.to_d
      { year: y, sales: sales, purchases: buys, cogs: cogs, profit: profit, margin: margin }
    end

    # ========= High-impact Charts datasets =========
    # 12-month trend (Revenue, COGS, Profit) ending at @end_date
    trend_start = (@end_date - 11.months).beginning_of_month
    trend_range = trend_start..@end_date
    month_key_expr = month_group_expr('sale_orders', 'order_date')

    rev_sql = "COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)"

    trend_rev = SaleOrderItem.joins(:sale_order)
                              .merge(so_scope.where(order_date: trend_range))
                              .group(Arel.sql(month_key_expr))
                              .sum(Arel.sql(rev_sql))
    trend_cogs = SaleOrderItem.joins(:sale_order)
                               .merge(so_scope.where(order_date: trend_range))
                               .group(Arel.sql(month_key_expr))
                               .sum(cogs_sql)

    # Normalize keys to YYYY-MM for consistent indexing across adapters
    trend_rev_map  = trend_rev.transform_keys { |k| normalize_month_key(k) }
    trend_cogs_map = trend_cogs.transform_keys { |k| normalize_month_key(k) }
    months_keys = (0..11).map { |i| (trend_start + i.months).strftime('%Y-%m') }
    @chart_sales_trend = {
      months: months_keys,
      revenue: months_keys.map { |k| (trend_rev_map[k] || 0).to_d },
      cogs:    months_keys.map { |k| (trend_cogs_map[k] || 0).to_d },
    }
    @chart_sales_trend[:profit] = @chart_sales_trend[:months].each_index.map do |i|
      @chart_sales_trend[:revenue][i] - @chart_sales_trend[:cogs][i]
    end

    # Sales by Product Category (current selection range)
    by_cat = SaleOrderItem.joins(:sale_order, :product)
                          .merge(so_ytd)
                          .group('products.category')
                          .sum(Arel.sql(rev_sql))
    # Order by value desc and keep top 5 + Others
    sorted = by_cat.to_a.sort_by { |(_, v)| -v.to_d }
    top5 = sorted.first(5)
    others_sum = sorted.drop(5).sum { |(_, v)| v.to_d }
    @chart_sales_by_category = top5.map { |(name, val)| { name: (name.presence || 'Uncategorized'), value: val.to_d } }
    @chart_sales_by_category << { name: 'Others', value: others_sum } if others_sum.positive?

    # Monthly stacked by category (YTD selection)
    by_month_cat = SaleOrderItem.joins(:sale_order, :product)
                                .merge(so_ytd)
                                .group(Arel.sql(month_key_expr), 'products.category')
                                .sum(Arel.sql(rev_sql))
    by_month_cat_norm = by_month_cat.transform_keys do |(mk, cat)|
      [normalize_month_key(mk), (cat.presence || 'Uncategorized')]
    end
    months_ytd_keys = months_between(@start_date.beginning_of_month, @end_date.end_of_month)
    # Top categories across YTD
    cats_totals = Hash.new(0.to_d)
    by_month_cat_norm.each { |((mk, cat)), val| cats_totals[cat] += val.to_d }
    top_cats = cats_totals.sort_by { |(_, v)| -v }.first(5).map(&:first)
    other_cats = cats_totals.keys - top_cats
    series = []
    top_cats.each do |cat|
      series << { name: cat, data: months_ytd_keys.map { |mk| (by_month_cat_norm[[mk, cat]] || 0).to_d } }
    end
    # Others collapsed
    if other_cats.any?
      series << { name: 'Others', data: months_ytd_keys.map { |mk| other_cats.sum { |c| (by_month_cat_norm[[mk, c]] || 0).to_d } } }
    end
    @chart_monthly_by_category = { months: months_ytd_keys, series: series }

    # Brand profitability (profit = revenue - cogs) for current selection
    by_brand_rev = SaleOrderItem.joins(:sale_order, :product)
                                .merge(so_ytd)
                                .group('products.brand')
                                .sum(Arel.sql(rev_sql))
    by_brand_cogs = SaleOrderItem.joins(:sale_order, :product)
                                 .merge(so_ytd)
                                 .group('products.brand')
                                 .sum(cogs_sql)
    brands = (by_brand_rev.keys + by_brand_cogs.keys).uniq
    brand_profit = brands.map do |b|
      rev  = by_brand_rev[b].to_d
      cogs = by_brand_cogs[b].to_d
      [b.presence || 'Unbranded', rev - cogs]
    end
    brand_profit.sort_by! { |(_, p)| -p }
    top_brands = brand_profit.first(8)
    @chart_brand_profit = {
      brands: top_brands.map(&:first),
      profit: top_brands.map { |(_, p)| p }
    }
  end

  # Returns JSON with geo aggregates for map visualizations
  # { visits: [{ name: "Mexico", value: 120 }], visits_by_region: [{ country: "Mexico", region: "Jalisco", value: 30 }],
  #   sales_by_region: [{ country: "Mexico", region: "CDMX", value: 9999.99 }], sales_by_country: [{ name: "Mexico", value: 120000.0 }] }
  def geo
    # Visits by country and region from VisitorLog
    visits_country = VisitorLog.where.not(country: [nil, ""]).group(:country).sum(:visit_count)
    visits_by_country = visits_country.map { |country, count| { name: country, value: count.to_i } }

    visits_region = VisitorLog.where.not(country: [nil, ""], region: [nil, ""]).group(:country, :region).sum(:visit_count)
    visits_by_region = visits_region.map { |(country, region), count| { country:, region:, value: count.to_i } }

    # Sales by country/region placeholder – will use shipping address when available.
    # For now, try infer from User.address basic region tokens if present (best-effort, optional)
    sales_by_region = []
    sales_by_country = []

    respond_to do |format|
      format.json do
        render json: {
          visits: visits_by_country,
          visits_by_region: visits_by_region,
          sales_by_region: sales_by_region,
          sales_by_country: sales_by_country
        }
      end
    end
  end

  private
  def authorize_admin!
    redirect_to root_path, alert: "Not authorized." unless current_user.admin?
  end

  # Adapter helpers for grouping by month/year
  def db_adapter
    ActiveRecord::Base.connection.adapter_name.to_s.downcase
  end

  # Returns a SQL expression string for grouping by month
  # table: e.g., 'sale_orders', column: e.g., 'order_date'
  def month_group_expr(table, column)
    col = "#{table}.#{column}"
    if db_adapter.include?('sqlite')
      # YYYY-MM-01 string
      "strftime('%Y-%m-01', #{col})"
    else
      # PostgreSQL
      "DATE_TRUNC('month', #{col})"
    end
  end

  # Returns a SQL expression string for grouping by year
  def year_group_expr(table, column)
    col = "#{table}.#{column}"
    if db_adapter.include?('sqlite')
      # YYYY string
      "strftime('%Y', #{col})"
    else
      # PostgreSQL
      "DATE_TRUNC('year', #{col})"
    end
  end

  # Normalize month key to 1..12 integer
  def extract_month_index(key)
    if key.respond_to?(:month)
      key.month
    elsif key.is_a?(String)
      begin
        Date.parse(key).month
      rescue ArgumentError
        nil
      end
    else
      nil
    end
  end

  # Normalize year key to integer
  def extract_year_index(key)
    if key.respond_to?(:year)
      key.year
    elsif key.is_a?(String)
      key.to_s[0,4].to_i
    else
      nil
    end
  end

  # Date range computation from params
  def compute_date_range(range_key, start_param, end_param, now)
    case range_key
    when 'last_30'
      [now.to_date - 30, now.end_of_day]
    when 'last_90'
      [now.to_date - 90, now.end_of_day]
    when 'this_year'
      [now.beginning_of_year.to_date, now.end_of_day]
    when 'custom'
      begin
        s = start_param.present? ? Date.parse(start_param) : now.beginning_of_year.to_date
        e = end_param.present? ? Time.zone.parse(end_param).end_of_day : now.end_of_day
        [s, e]
      rescue ArgumentError
        [now.beginning_of_year.to_date, now.end_of_day]
      end
    else # 'ytd'
      [now.beginning_of_year.to_date, now.end_of_day]
    end
  end

  # Normalize grouped month key (adapter-agnostic) to 'YYYY-MM'
  def normalize_month_key(key)
    if key.is_a?(String)
      # SQLite strftime('%Y-%m-01') or '%Y-%m'
      key[0,7]
    elsif key.respond_to?(:to_date)
      key.to_date.strftime('%Y-%m')
    else
      key.to_s[0,7]
    end
  end

  # Generate inclusive month keys from start..end as ['YYYY-MM', ...]
  def months_between(start_date, end_date)
    start_d = start_date.to_date.beginning_of_month
    end_d   = end_date.to_date.end_of_month
    months = []
    d = start_d
    while d <= end_d
      months << d.strftime('%Y-%m')
      d = d.next_month.beginning_of_month
    end
    months
  end
end
