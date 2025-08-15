class Admin::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  layout "admin"

  def index
    # Timeframe base
    now         = Time.zone.now
    year_start  = now.beginning_of_year
    range_ytd   = year_start..now.end_of_day

    # Scopes base (excluir canceladas)
    so_scope = SaleOrder.where.not(status: "Canceled")
    po_scope = PurchaseOrder.where.not(status: "Canceled")

    so_ytd = so_scope.where(order_date: range_ytd)
    po_ytd = po_scope.where(order_date: range_ytd)

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

    # Tabla mensual del año en curso
    sales_monthly = so_ytd.group("DATE_TRUNC('month', order_date)").sum(:total_order_value)
    cogs_monthly  = SaleOrderItem.joins(:sale_order)
                                 .merge(so_ytd)
                                 .group("DATE_TRUNC('month', sale_orders.order_date)")
                                 .sum(cogs_sql)
    purchases_monthly = po_ytd.group("DATE_TRUNC('month', order_date)").sum(:total_cost_mxn)

    sales_m_map     = sales_monthly.transform_keys { |t| t.month }
    cogs_m_map      = cogs_monthly.transform_keys { |t| t.month }
    purchases_m_map = purchases_monthly.transform_keys { |t| t.month }

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

    # Tabla anual (últimos 5 años)
    years = ((now.year - 4)..now.year).to_a
    so_5y = so_scope.where(order_date: (now.beginning_of_year - 4.years)..now.end_of_year)
    po_5y = po_scope.where(order_date: (now.beginning_of_year - 4.years)..now.end_of_year)

    sales_yearly = so_5y.group("DATE_TRUNC('year', order_date)").sum(:total_order_value)
    cogs_yearly  = SaleOrderItem.joins(:sale_order)
                                .merge(so_5y)
                                .group("DATE_TRUNC('year', sale_orders.order_date)")
                                .sum(cogs_sql)
    purchases_yearly = po_5y.group("DATE_TRUNC('year', order_date)").sum(:total_cost_mxn)

    sales_y_map     = sales_yearly.transform_keys { |t| t.year }
    cogs_y_map      = cogs_yearly.transform_keys { |t| t.year }
    purchases_y_map = purchases_yearly.transform_keys { |t| t.year }

    @annual_stats = years.map do |y|
      sales = (sales_y_map[y] || 0).to_d
      cogs  = (cogs_y_map[y] || 0).to_d
      buys  = (purchases_y_map[y] || 0).to_d
      profit = sales - cogs
      margin = sales.positive? ? (profit / sales) : 0.to_d
      { year: y, sales: sales, purchases: buys, cogs: cogs, profit: profit, margin: margin }
    end
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
end
