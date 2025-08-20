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
  paid_statuses = %w[Confirmed Shipped Delivered]
  so_ytd_paid = so_ytd.where(status: paid_statuses)
  po_ytd = po_scope.where(order_date: range)

    # KPIs básicos
    @total_products = Product.active.count rescue Product.count
    @total_users    = User.count

  # Ventas/Compras YTD
    rev_sql_arel = Arel.sql("COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)")
    @sales_ytd     = SaleOrderItem.joins(:sale_order)
                                  .merge(so_ytd)
                                  .sum(rev_sql_arel).to_d
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

    # KPI adicionales
  @orders_count_ytd      = so_ytd.count
  @po_count_ytd          = po_ytd.count
    @active_customers_ytd  = so_ytd.select(:user_id).distinct.count
    @inventory_total_value = Product.sum(:current_inventory_value).to_d
  # Cantidades de artículos en el rango
  @po_items_qty_ytd = PurchaseOrderItem.joins(:purchase_order).merge(po_ytd).sum(:quantity).to_i
  @so_items_qty_ytd = SaleOrderItem.joins(:sale_order).merge(so_ytd).sum(:quantity).to_i

    # Compras totales (MXN) all-time (respeta excluir canceladas)
    @purchases_total_mxn = po_scope.sum(:total_cost_mxn).to_d
    if @purchases_total_mxn.zero?
      # Fallback si total_cost_mxn aún no existía/estaba vacío
      @purchases_total_mxn = po_scope.sum(:total_order_cost).to_d
    end

    # Comparativa YTD vs mismo periodo del año anterior
  range_prev_start = @start_date.prev_year
    range_prev_end   = @end_date.prev_year
  so_prev_range = so_scope.where(order_date: range_prev_start..range_prev_end)
  po_prev_range = po_scope.where(order_date: range_prev_start..range_prev_end)
  @sales_prev   = SaleOrderItem.joins(:sale_order)
                 .merge(so_prev_range)
                 .sum(rev_sql_arel).to_d
    @cogs_prev    = SaleOrderItem.joins(:sale_order).merge(so_prev_range).sum(cogs_sql).to_d
    @profit_prev  = @sales_prev - @cogs_prev
    @margin_prev  = @sales_prev.positive? ? (@profit_prev / @sales_prev) : 0.to_d
  @orders_prev  = so_prev_range.count
  @po_count_prev = po_prev_range.count
    @active_customers_prev = so_prev_range.select(:user_id).distinct.count

    # Deltas (% vs LY) y puntos porcentuales para margen
    def pct_delta(curr, prev)
      prev.to_d.positive? ? ((curr.to_d - prev.to_d) / prev.to_d) : nil
    end
    @kpi_deltas = {
      sales:   pct_delta(@sales_ytd, @sales_prev),
      profit:  pct_delta(@profit_ytd, @profit_prev),
      orders:  pct_delta(@orders_count_ytd, @orders_prev),
      po_count: pct_delta(@po_count_ytd, @po_count_prev),
      customers: pct_delta(@active_customers_ytd, @active_customers_prev),
      margin_pp: (@margin_ytd - @margin_prev) # diferencia absoluta (puntos)
    }

    # Ticket promedio y conversión (si hay visitas)
    @avg_ticket_ytd = @orders_count_ytd.positive? ? (@sales_ytd / @orders_count_ytd) : 0.to_d
    begin
      @visits_total = VisitorLog.sum(:visit_count)
    rescue
      @visits_total = nil
    end
    @conversion_rate_ytd = (@visits_total.to_i > 0) ? (@orders_count_ytd.to_d / @visits_total.to_d) : nil

    # Clientes nuevos vs recurrentes (nuevos = primera orden en el rango YTD)
    first_order_by_user = so_scope.group(:user_id).minimum(:order_date)
    @new_customers_ytd = first_order_by_user.values.count { |d| d && d >= @start_date && d <= @end_date }
    @recurring_customers_ytd = @active_customers_ytd - @new_customers_ytd
    @recurring_customers_ratio = @active_customers_ytd.positive? ? (@recurring_customers_ytd.to_d / @active_customers_ytd) : nil

    # Stock crítico (productos con inventario libre <= punto de reorden > 0)
    begin
      free_counts = Inventory.free.group(:product_id).count
      rp_map = Product.where("reorder_point IS NOT NULL AND reorder_point > 0").pluck(:id, :reorder_point).to_h
      @critical_stock_count = rp_map.count { |pid, rp| free_counts.fetch(pid, 0).to_i <= rp.to_i }
    rescue => _e
      @critical_stock_count = nil
    end

    # Rotación de inventario aproximada (COGS YTD / inventario promedio). Sin histórico, usar total actual como aproximación.
    @inventory_turnover_ytd = @inventory_total_value.positive? ? (@cogs_ytd / @inventory_total_value) : nil

  # Ventas totales (MXN) All Time (respeta excluir canceladas)
  @sales_total_mxn = SaleOrderItem.joins(:sale_order)
                   .merge(so_scope)
                   .sum(rev_sql_arel).to_d

  # Totales all-time de conteo (respeta excluir canceladas)
  @so_total_all_time = so_scope.count
  @po_total_all_time = po_scope.count
  # Totales all-time de artículos comprados/vendidos (respeta excluir canceladas)
  @po_items_qty_all_time = PurchaseOrderItem.joins(:purchase_order).merge(po_scope).sum(:quantity).to_i
  @so_items_qty_all_time = SaleOrderItem.joins(:sale_order).merge(so_scope).sum(:quantity).to_i

  # Top 10 productos históricos (por unidades)
    rev_sql = "COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)"
  top_products = SaleOrderItem.joins(:sale_order, :product)
                .merge(so_scope.where(status: paid_statuses))
                .group("products.id", "products.product_name", "products.brand", "products.category")
                .select("products.id, products.product_name, products.brand, products.category, SUM(sale_order_items.quantity) AS units, SUM(#{rev_sql}) AS revenue")
                                .order("units DESC")
                .limit(10)
  @top_products_all = top_products.map { |r| { product_id: r.id, name: r.product_name, brand: r.brand, category: r.category, units: r.attributes["units"].to_i, revenue: r.attributes["revenue"].to_d } }

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

  # Top 10 usuarios con mayores compras históricas (por ingresos en MXN a partir de items)
    users_top = SaleOrderItem.joins(sale_order: :user)
                             .merge(so_scope)
                             .group("users.id", "users.name")
                             .select("users.id, users.name, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{rev_sql}) AS revenue")
                             .order("revenue DESC")
                             .limit(10)
    @top_users_all = users_top.map { |r| { user_id: r.id, name: r.name.presence || r.id, orders_count: r.attributes["orders_count"].to_i, revenue: r.attributes["revenue"].to_d } }

  # Top 10 users within current range (YTD por defecto) usando items en MXN
  users_top_range = SaleOrderItem.joins(sale_order: :user)
                                 .merge(so_ytd)
                                 .group("users.id", "users.name")
                                 .select("users.id, users.name, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{rev_sql}) AS revenue")
                                 .order("revenue DESC")
                                 .limit(10)
  @top_users_range = users_top_range.map { |r| { user_id: r.id, name: r.name.presence || r.id, orders_count: r.attributes["orders_count"].to_i, revenue: r.attributes["revenue"].to_d } }

  # Top 10 users Last Year (calendario completo)
  ly_start_users = now.beginning_of_year - 1.year
  ly_end_users   = ly_start_users.end_of_year
  so_last_year_users = so_scope.where(order_date: ly_start_users..ly_end_users)
  users_top_last_year = SaleOrderItem.joins(sale_order: :user)
                                     .merge(so_last_year_users)
                                     .group("users.id", "users.name")
                                     .select("users.id, users.name, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{rev_sql}) AS revenue")
                                     .order("revenue DESC")
                                     .limit(10)
  @top_users_last_year = users_top_last_year.map { |r| { user_id: r.id, name: r.name.presence || r.id, orders_count: r.attributes["orders_count"].to_i, revenue: r.attributes["revenue"].to_d } }

  # Comparativo YTD vs mismo periodo del año pasado para Top Customers (solo para la pestaña YTD) usando items en MXN
  users_prev_rows = SaleOrderItem.joins(sale_order: :user)
                                 .merge(so_prev_range)
                                 .group("users.id")
                                 .select("users.id, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{rev_sql}) AS revenue")
  prev_map = {}
  users_prev_rows.each do |r|
    prev_map[r.id] = { orders_count: r.attributes["orders_count"].to_i, revenue: r.attributes["revenue"].to_d }
  end

  # Turbo Frame: lista de Top Sellers por periodo
  def sellers
    authorize_admin!
    now = Time.zone.now
    period = params[:period].presence || 'ytd' # ytd | ly | all
    page = params[:page].presence || 1
    per  = (params[:per].presence || 10).to_i.clamp(5, 50)

    so_scope = SaleOrder.where.not(status: 'Canceled')
    paid_statuses = %w[Confirmed Shipped Delivered]
    # Rango temporal base (sin filtrar por estatus aún)
    base_scope = case period
                 when 'ly'
                   ly_start = now.beginning_of_year - 1.year
                   ly_end   = ly_start.end_of_year
                   so_scope.where(order_date: ly_start..ly_end)
                 when 'all'
                   so_scope
                 else # 'ytd'
                   so_scope.where(order_date: (now.beginning_of_year..now.end_of_day))
                 end
    # Preferimos órdenes “pagadas”; si no hay resultados, caemos a "todas excepto canceladas" para evitar tablero vacío en dev
    primary_scope   = base_scope.where(status: paid_statuses)
    fallback_scope  = base_scope

    rev_sql  = "COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)"
    units_sql = "COALESCE(sale_order_items.quantity, 0)"
    build_rel = lambda do |scope|
      SaleOrderItem.joins(:sale_order, :product)
                   .merge(scope)
                   .group('products.id','products.product_name','products.brand','products.category')
                   .select("products.id, products.product_name, products.brand, products.category, SUM(#{units_sql}) AS units, SUM(#{rev_sql}) AS revenue")
                   .order('units DESC')
    end

    rel = build_rel.call(primary_scope).page(page).per(per)
    if rel.total_count.to_i == 0
      rel = build_rel.call(fallback_scope).page(page).per(per)
    end

  @rows = rel.map { |r| { product_id: r.id, name: r.product_name, brand: r.brand, category: r.category, units: r.attributes['units'].to_i, revenue: r.attributes['revenue'].to_d } }
  @period = period
  @rel = rel

    respond_to do |format|
      format.html { render :sellers, layout: false }
    end
  end

  # Turbo Frame: productos rentables (profit) por periodo
  def profitable
    authorize_admin!
    now = Time.zone.now
    period = params[:period].presence || 'ytd'
    page = params[:page].presence || 1
    per  = (params[:per].presence || 10).to_i.clamp(5, 50)

    so_scope = SaleOrder.where.not(status: 'Canceled')
    paid_statuses = %w[Confirmed Shipped Delivered]
    scope = case period
            when 'ly'
              ly_start = now.beginning_of_year - 1.year
              ly_end   = ly_start.end_of_year
              so_scope.where(order_date: ly_start..ly_end).where(status: paid_statuses)
            when 'all'
              so_scope.where(status: paid_statuses)
            else
              so_scope.where(order_date: (now.beginning_of_year..now.end_of_day)).where(status: paid_statuses)
            end

    rev_sql   = "COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)"
    cogs_sql  = "COALESCE(sale_order_items.unit_cost, 0) * COALESCE(sale_order_items.quantity, 0)"

  sales = SaleOrderItem.joins(:sale_order, :product)
             .merge(scope)
             .group('products.id','products.product_name','products.brand','products.category')
             .select("products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(#{rev_sql}) AS revenue")
    cogs  = SaleOrderItem.joins(:sale_order, :product)
                         .merge(scope)
                         .group('products.id')
                         .select("products.id AS product_id, SUM(#{cogs_sql}) AS cogs")

    cogs_map = cogs.index_by { |r| r.attributes['product_id'].to_i }

  rel = sales.select('SUM('+rev_sql+') - COALESCE(SUM('+cogs_sql+'),0) AS profit')
         .order('profit DESC')
    rel = rel.page(page).per(per)
  @rows = rel.map do |r|
      pid = r.attributes['product_id'].to_i
      {
        product_id: pid,
        name: r.attributes['product_name'],
        brand: r.attributes['brand'],
        category: r.attributes['category'],
  revenue: (r.attributes['revenue'] || 0).to_d,
  cogs: (cogs_map[pid]&.attributes&.dig('cogs') || 0).to_d,
        profit: r.attributes['profit'].to_d
      }
    end
  @period = period
  @rel = rel
    respond_to do |format|
      format.html { render :profitable, layout: false }
    end
  end

  # Turbo Frame: Top Inventario (por valor/unidades y scope inv/res/all)
  def inventory_top
    authorize_admin!
    scope = params[:scope].presence || 'inv'  # inv | res | all
    metric = params[:metric].presence || 'value' # value | qty
    page = params[:page].presence || 1
    per  = (params[:per].presence || 10).to_i.clamp(5, 50)

    statuses = case scope
               when 'res' then [:reserved, :pre_reserved, :pre_sold]
               when 'all' then [:available, :in_transit, :reserved, :pre_reserved, :pre_sold]
               else [:available, :in_transit]
               end

    base = Inventory.joins(:product)
                    .where(status: statuses)
                    .group('products.id','products.product_name','products.brand','products.category')

    rel = if metric == 'qty'
            base.select('products.id, products.product_name, products.brand, products.category, COUNT(inventories.id) AS units_count, SUM(inventories.purchase_cost) AS inventory_value')
                .order('units_count DESC')
          else
            base.select('products.id, products.product_name, products.brand, products.category, SUM(inventories.purchase_cost) AS inventory_value')
                .order('inventory_value DESC')
          end

    rel = rel.page(page).per(per)
  @rows = rel.map do |r|
      {
        product_id: r.id,
        name: r.product_name,
        brand: r.brand,
        category: r.category,
        units_count: r.try(:attributes).try(:[], 'units_count').to_i,
        inventory_value: r.try(:attributes).try(:[], 'inventory_value').to_d
      }
    end
  @scope = scope
  @metric = metric
  @rel = rel
    respond_to do |format|
      format.html { render :inventory_top, layout: false }
    end
  end

  # Turbo Frame: Top Categorías por periodo y métrica (rev|profit)
  def categories_rank
    authorize_admin!
    now = Time.zone.now
    period = params[:period].presence || 'ytd'
    metric = params[:metric].presence || 'rev' # rev | profit
    page = (params[:page].presence || 1)
    per  = (params[:per].presence || 10).to_i.clamp(5, 50)

    so_scope = SaleOrder.where.not(status: 'Canceled')
    range_scope = case period
                  when 'ly'
                    ly_start = now.beginning_of_year - 1.year
                    so_scope.where(order_date: ly_start..ly_start.end_of_year)
                  when 'all'
                    so_scope
                  else
                    so_scope.where(order_date: now.beginning_of_year..now.end_of_day)
                  end

    rev_sql = Arel.sql("COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)")
    cogs_sql = Arel.sql("COALESCE(sale_order_items.unit_cost, 0) * COALESCE(sale_order_items.quantity, 0)")

    by_cat_rev = SaleOrderItem.joins(:sale_order, :product)
                               .merge(range_scope)
                               .group('products.category')
                               .sum(rev_sql)
    rows = if metric == 'profit'
             by_cat_cogs = SaleOrderItem.joins(:sale_order, :product)
                                        .merge(range_scope)
                                        .group('products.category')
                                        .sum(cogs_sql)
             cats = (by_cat_rev.keys + by_cat_cogs.keys).uniq
             cats.map do |cat|
               rev = by_cat_rev[cat].to_d
               cogs = by_cat_cogs[cat].to_d
               { category: (cat.presence || 'Uncategorized'), value: (rev - cogs) }
             end
           else
             by_cat_rev.map { |cat, val| { category: (cat.presence || 'Uncategorized'), value: val.to_d } }
           end
    rows.sort_by! { |h| -h[:value].to_d }
    rel = Kaminari.paginate_array(rows).page(page).per(per)
    @rows = rel
    @period = period
    @metric = metric
    @rel = rel
    respond_to do |format|
      format.html { render :categories_rank, layout: false }
    end
  end

  # Turbo Frame: Top Customers por periodo y métrica (sales|reserved|combined)
  def customers_rank
    authorize_admin!
    now = Time.zone.now
    period = params[:period].presence || 'ytd'
    metric = params[:metric].presence || 'sales' # sales | reserved | combined
    page = (params[:page].presence || 1)
    per  = (params[:per].presence || 10).to_i.clamp(5, 50)

    so_scope = SaleOrder.where.not(status: 'Canceled')
    paid_statuses = %w[Confirmed Shipped Delivered]
    range_scope = case period
                  when 'ly'
                    ly_start = now.beginning_of_year - 1.year
                    so_scope.where(order_date: ly_start..ly_start.end_of_year)
                  when 'all'
                    so_scope
                  else
                    so_scope.where(order_date: now.beginning_of_year..now.end_of_day)
                  end

    # Sales per user within range
    rev_sql = "COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)"
    sales_rows = SaleOrderItem.joins(sale_order: :user)
                              .merge(range_scope.where(status: paid_statuses))
                              .group('users.id','users.name')
                              .select("users.id AS user_id, users.name AS name, COUNT(DISTINCT sale_orders.id) AS orders_count, SUM(#{rev_sql}) AS revenue")

    # Reserved per user within range
    reserved_statuses = [:reserved, :pre_reserved, :pre_sold]
    reserved_rows = Inventory.joins(sale_order: :user)
                             .merge(range_scope)
                             .where(status: reserved_statuses)
                             .group('users.id','users.name')
                             .select('users.id AS user_id, users.name AS name, COUNT(inventories.id) AS units_reserved, SUM(inventories.purchase_cost) AS reserved_value')

    rows = case metric
           when 'reserved'
             reserved_rows.map { |r| { user_id: r.attributes['user_id'].to_i, name: (r.attributes['name'].presence || r.attributes['user_id']), units_reserved: r.attributes['units_reserved'].to_i, reserved_value: r.attributes['reserved_value'].to_d } }
                       .sort_by { |h| -h[:reserved_value] }
           when 'combined'
             s_map = sales_rows.index_by { |r| r.attributes['user_id'].to_i }
             r_map = reserved_rows.index_by { |r| r.attributes['user_id'].to_i }
             (s_map.keys + r_map.keys).uniq.map do |uid|
               s = s_map[uid]
               r = r_map[uid]
               name = (s&.attributes&.dig('name').presence || r&.attributes&.dig('name').presence || uid)
               orders = s&.attributes&.dig('orders_count').to_i
               revenue = s&.attributes&.dig('revenue').to_d
               units_reserved = r&.attributes&.dig('units_reserved').to_i
               reserved_value = r&.attributes&.dig('reserved_value').to_d
               total = revenue + reserved_value
               { user_id: uid, name:, orders_count: orders, revenue:, units_reserved:, reserved_value:, total: total }
             end.sort_by { |h| -h[:total] }
           else # 'sales'
             sales_rows.map { |r| { user_id: r.attributes['user_id'].to_i, name: (r.attributes['name'].presence || r.attributes['user_id']), orders_count: r.attributes['orders_count'].to_i, revenue: r.attributes['revenue'].to_d } }
                       .sort_by { |h| -h[:revenue] }
           end

    rel = Kaminari.paginate_array(rows).page(page).per(per)
    @rows = rel
    @period = period
    @metric = metric
    @rel = rel
    respond_to do |format|
      format.html { render :customers_rank, layout: false }
    end
  end
  @top_users_ytd_vs_prev = @top_users_range.map do |u|
    prev = prev_map[u[:user_id]] || { orders_count: 0, revenue: 0.to_d }
    delta = prev[:revenue].to_d.positive? ? ((u[:revenue] - prev[:revenue]) / prev[:revenue]) : nil
    u.merge(prev_orders_count: prev[:orders_count], prev_revenue: prev[:revenue], revenue_delta_ratio: delta)
  end

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

      # ========= Tablas de apoyo para promociones =========
    rev_sql_str = "COALESCE(sale_order_items.unit_final_price, 0) * COALESCE(sale_order_items.quantity, 0)"
    cogs_sql_str = "COALESCE(sale_order_items.unit_cost, 0) * COALESCE(sale_order_items.quantity, 0)"
      units_sql   = "COALESCE(sale_order_items.quantity, 0)"

      # Top Sellers (por unidades) en el rango YTD seleccionado
  top_sellers_q = SaleOrderItem.joins(:sale_order, :product)
               .merge(so_ytd_paid)
                                   .group('products.id','products.product_name','products.brand','products.category')
                                   .select("products.id, products.product_name, products.brand, products.category, SUM(#{units_sql}) AS units, SUM(#{rev_sql_str}) AS revenue")
                                   .order('units DESC')
                                   .limit(10)
      @top_sellers_ytd = top_sellers_q.map { |r| { product_id: r.id, name: r.product_name, brand: r.brand, category: r.category, units: r.attributes['units'].to_i, revenue: r.attributes['revenue'].to_d } }

  # Top Sellers (Last Year calendario completo)
  ly_start = now.beginning_of_year - 1.year
  ly_end   = ly_start.end_of_year
  so_last_year = so_scope.where(order_date: ly_start..ly_end)
  so_last_year_paid = so_last_year.where(status: paid_statuses)
  top_sellers_ly_q = SaleOrderItem.joins(:sale_order, :product)
              .merge(so_last_year_paid)
              .group('products.id','products.product_name','products.brand','products.category')
              .select("products.id, products.product_name, products.brand, products.category, SUM(#{units_sql}) AS units, SUM(#{rev_sql_str}) AS revenue")
              .order('units DESC')
              .limit(10)
  @top_sellers_last_year = top_sellers_ly_q.map { |r| { product_id: r.id, name: r.product_name, brand: r.brand, category: r.category, units: r.attributes['units'].to_i, revenue: r.attributes['revenue'].to_d } }

  # Top Sellers (All Time) por unidades ya existe en @top_products_all

      # Top inventario (por valor y por unidades) con filtros: Inventario, Apartados, Todo
      inv_only_statuses   = [:available, :in_transit]
      reserved_statuses   = [:reserved, :pre_reserved, :pre_sold]
      inv_all_statuses    = inv_only_statuses + reserved_statuses

      build_top_inv = lambda do |statuses, order_by|
        base = Inventory.joins(:product)
                         .where(status: statuses)
                         .group('products.id', 'products.product_name', 'products.brand', 'products.category')
        rows_v = base.select('products.id, products.product_name, products.brand, products.category, SUM(inventories.purchase_cost) AS inventory_value')
                     .order('inventory_value DESC')
                     .limit(10)
        by_value = rows_v.map { |r| { product_id: r.id, name: r.product_name, brand: r.brand, category: r.category, inventory_value: r.attributes['inventory_value'].to_d } }

        rows_q = base.select('products.id, products.product_name, products.brand, products.category, COUNT(inventories.id) AS units_count, SUM(inventories.purchase_cost) AS inventory_value')
                     .order('units_count DESC')
                     .limit(10)
        by_qty = rows_q.map { |r| { product_id: r.id, name: r.product_name, brand: r.brand, category: r.category, units_count: r.attributes['units_count'].to_i, inventory_value: r.attributes['inventory_value'].to_d } }
        [by_value, by_qty]
      end

      @top_inventory_by_value_inventory, @top_inventory_by_quantity_inventory = build_top_inv.call(inv_only_statuses, 'value')
      @top_inventory_by_value_reserved,  @top_inventory_by_quantity_reserved  = build_top_inv.call(reserved_statuses, 'value')
      @top_inventory_by_value_all,       @top_inventory_by_quantity_all       = build_top_inv.call(inv_all_statuses, 'value')

      # Back-compat variables used by the view previously (point to "all")
      @top_inventory_by_value    = @top_inventory_by_value_all
      @top_inventory_by_quantity = @top_inventory_by_quantity_all

      # Top ventas por categoría (YTD actual)
      ytd_by_cat = SaleOrderItem.joins(:sale_order, :product)
                                .merge(so_ytd)
                                .group('products.category')
                                .sum(Arel.sql(rev_sql_str))
  @top_categories_ytd = ytd_by_cat.to_a.map { |(cat, val)| { category: (cat.presence || 'Uncategorized'), revenue: val.to_d } }
               .sort_by { |h| -h[:revenue] }
               .first(10)
      # Utilidad por categoría (YTD): revenue - cogs
      ytd_cogs_by_cat = SaleOrderItem.joins(:sale_order, :product)
                                     .merge(so_ytd)
                                     .group('products.category')
                                     .sum(Arel.sql(cogs_sql_str))
      cats_ytd = (ytd_by_cat.keys + ytd_cogs_by_cat.keys).uniq
      @top_categories_profit_ytd = cats_ytd.map do |cat|
        rev  = ytd_by_cat[cat].to_d
        cogs = ytd_cogs_by_cat[cat].to_d
        { category: (cat.presence || 'Uncategorized'), profit: (rev - cogs) }
      end.sort_by { |h| -h[:profit] }.first(10)

      # Top ventas por categoría (año pasado calendario completo)
      prev_start = now.beginning_of_year - 1.year
      prev_end   = prev_start.end_of_year
      so_prev    = so_scope.where(order_date: prev_start..prev_end)
      prev_by_cat = SaleOrderItem.joins(:sale_order, :product)
                                 .merge(so_prev)
                                 .group('products.category')
                                 .sum(Arel.sql(rev_sql_str))
  @top_categories_last_year = prev_by_cat.to_a.map { |(cat, val)| { category: (cat.presence || 'Uncategorized'), revenue: val.to_d } }
              .sort_by { |h| -h[:revenue] }
              .first(10)
      # Utilidad por categoría (Last Year)
      prev_cogs_by_cat = SaleOrderItem.joins(:sale_order, :product)
                                      .merge(so_prev)
                                      .group('products.category')
                                      .sum(Arel.sql(cogs_sql_str))
      cats_prev = (prev_by_cat.keys + prev_cogs_by_cat.keys).uniq
      @top_categories_profit_last_year = cats_prev.map do |cat|
        rev  = prev_by_cat[cat].to_d
        cogs = prev_cogs_by_cat[cat].to_d
        { category: (cat.presence || 'Uncategorized'), profit: (rev - cogs) }
      end.sort_by { |h| -h[:profit] }.first(10)

  # Top ventas por categoría (All Time)
  all_by_cat = SaleOrderItem.joins(:sale_order, :product)
            .merge(so_scope)
            .group('products.category')
            .sum(Arel.sql(rev_sql_str))
  @top_categories_all_time = all_by_cat.to_a.map { |(cat, val)| { category: (cat.presence || 'Uncategorized'), revenue: val.to_d } }
            .sort_by { |h| -h[:revenue] }
            .first(10)
  # Utilidad por categoría (All Time)
  all_cogs_by_cat = SaleOrderItem.joins(:sale_order, :product)
                                 .merge(so_scope)
                                 .group('products.category')
                                 .sum(Arel.sql(cogs_sql_str))
  cats_all = (all_by_cat.keys + all_cogs_by_cat.keys).uniq
  @top_categories_profit_all_time = cats_all.map do |cat|
    rev  = all_by_cat[cat].to_d
    cogs = all_cogs_by_cat[cat].to_d
    { category: (cat.presence || 'Uncategorized'), profit: (rev - cogs) }
  end.sort_by { |h| -h[:profit] }.first(10)

  # ============== Top Customers: Apartados (reserved/pre_reserved/pre_sold) ==============
  reserved_statuses = [:reserved, :pre_reserved, :pre_sold]
  build_top_reserved = lambda do |scope|
    rows = Inventory.joins(sale_order: :user)
                    .merge(scope)
                    .where(status: reserved_statuses)
                    .group('users.id','users.name')
                    .select("users.id, users.name, COUNT(inventories.id) AS units_reserved, SUM(inventories.purchase_cost) AS reserved_value")
                    .order('reserved_value DESC')
                    .limit(10)
    rows.map { |r| { user_id: r.id, name: (r.name.presence || r.id), units_reserved: r.attributes['units_reserved'].to_i, reserved_value: r.attributes['reserved_value'].to_d } }
  end

  @top_users_reserved_ytd = build_top_reserved.call(so_ytd)
  @top_users_reserved_last_year = build_top_reserved.call(so_last_year_users)
  @top_users_reserved_all = build_top_reserved.call(so_scope)

  # Combine Sales + Reserved per user and rank by (revenue + reserved_value)
  combine_sales_reserved = lambda do |sales_rows, reserved_rows|
    s_map = (sales_rows || []).index_by { |r| r[:user_id] }
    r_map = (reserved_rows || []).index_by { |r| r[:user_id] }
    (s_map.keys + r_map.keys).uniq.map do |uid|
      s = s_map[uid]
      r = r_map[uid]
      name = (s && s[:name]).presence || (r && r[:name]).presence || uid
      orders = s ? s[:orders_count].to_i : 0
      revenue = s ? s[:revenue].to_d : 0.to_d
      units_reserved = r ? r[:units_reserved].to_i : 0
      reserved_value = r ? r[:reserved_value].to_d : 0.to_d
      total = revenue + reserved_value
      { user_id: uid, name: name, orders_count: orders, revenue: revenue, units_reserved: units_reserved, reserved_value: reserved_value, total: total }
    end.sort_by { |h| -h[:total] }.first(10)
  end

  @top_users_sales_reserved_ytd = combine_sales_reserved.call(@top_users_range, @top_users_reserved_ytd)
  @top_users_sales_reserved_last_year = combine_sales_reserved.call(@top_users_last_year, @top_users_reserved_last_year)
  @top_users_sales_reserved_all = combine_sales_reserved.call(@top_users_all, @top_users_reserved_all)

    # Productos más rentables (YTD): Ventas (ingresos), COGS (costo de unidades vendidas en el periodo), Utilidad = Ventas - COGS - Mermas
  sales_rows_ytd = SaleOrderItem.joins(:sale_order, :product)
      .merge(so_ytd_paid)
                  .group('products.id','products.product_name','products.brand','products.category')
                  .select("products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(#{rev_sql_str}) AS sales_total")
  # Merma (marketing, damaged, lost, scrap) costo por producto en el rango
  waste_rows_ytd = Inventory.joins(:product)
            .where(status: [:marketing, :damaged, :lost, :scrap], status_changed_at: range)
            .group('products.id','products.product_name','products.brand','products.category')
            .select('products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(inventories.purchase_cost) AS waste_total')

  waste_map_ytd = waste_rows_ytd.index_by { |r| r.attributes['product_id'].to_i }

  # Prefer COGS from Inventory purchase_cost for sold items (paid orders) in period; fallback to SOI.unit_cost
  cogs_rows_ytd_inv = Inventory.joins(:product, :sale_order)
                               .merge(so_ytd_paid)
                               .where(status: :sold)
                               .group('products.id','products.product_name','products.brand','products.category')
                               .select('products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(inventories.purchase_cost) AS cogs_total')
  if cogs_rows_ytd_inv.any?
    cogs_rows_ytd = cogs_rows_ytd_inv
  else
    cogs_rows_ytd = SaleOrderItem.joins(:sale_order, :product)
                   .merge(so_ytd_paid)
                   .group('products.id','products.product_name','products.brand','products.category')
                   .select("products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(#{cogs_sql_str}) AS cogs_total")
  end

  sales_map_ytd = sales_rows_ytd.index_by { |r| r.attributes['product_id'].to_i }
  cogs_map_ytd  = cogs_rows_ytd.index_by { |r| r.attributes['product_id'].to_i }
  all_ids_ytd   = (sales_map_ytd.keys + cogs_map_ytd.keys + waste_map_ytd.keys).uniq

      prod_profit = all_ids_ytd.map do |pid|
        srow = sales_map_ytd[pid]
  name = srow&.attributes&.dig('product_name')
  brand = srow&.attributes&.dig('brand')
  cat  = srow&.attributes&.dig('category')
        sales     = srow&.attributes&.dig('sales_total').to_d
  purchases = cogs_map_ytd[pid]&.attributes&.dig('cogs_total').to_d
        waste     = waste_map_ytd[pid]&.attributes&.dig('waste_total').to_d
        {
          product_id: pid,
          name: name,
          brand: brand,
          category: (cat.presence || 'Uncategorized'),
          revenue: sales,      # Ventas
          cogs: purchases,     # Compra (inversión)
          profit: sales - purchases - waste # Utilidad neta tras mermas
        }
      end

      @top_products_profit_ytd = prod_profit.sort_by { |h| -h[:profit] }.first(10)

  # Productos más rentables (Last Year calendario completo)

  sales_rows_ly = SaleOrderItem.joins(:sale_order, :product)
               .merge(so_last_year_paid)
                                   .group('products.id','products.product_name','products.brand','products.category')
                                   .select("products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(#{rev_sql_str}) AS sales_total")
  waste_rows_ly = Inventory.joins(:product)
           .where(status: [:marketing, :damaged, :lost, :scrap], status_changed_at: ly_start..ly_end)
           .group('products.id','products.product_name','products.brand','products.category')
           .select('products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(inventories.purchase_cost) AS waste_total')
  waste_map_ly = waste_rows_ly.index_by { |r| r.attributes['product_id'].to_i }

  cogs_rows_ly_inv = Inventory.joins(:product, :sale_order)
                             .merge(so_last_year_paid)
                             .where(status: :sold)
                             .group('products.id','products.product_name','products.brand','products.category')
                             .select('products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(inventories.purchase_cost) AS cogs_total')
  if cogs_rows_ly_inv.any?
    cogs_rows_ly = cogs_rows_ly_inv
  else
    cogs_rows_ly = SaleOrderItem.joins(:sale_order, :product)
                .merge(so_last_year_paid)
                .group('products.id','products.product_name','products.brand','products.category')
                .select("products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(#{cogs_sql_str}) AS cogs_total")
  end

  sales_map_ly = sales_rows_ly.index_by { |r| r.attributes['product_id'].to_i }
  cogs_map_ly  = cogs_rows_ly.index_by { |r| r.attributes['product_id'].to_i }
  all_ids_ly   = (sales_map_ly.keys + cogs_map_ly.keys + waste_map_ly.keys).uniq

      prod_profit_ly = all_ids_ly.map do |pid|
        srow = sales_map_ly[pid]
  name = srow&.attributes&.dig('product_name')
  brand = srow&.attributes&.dig('brand')
  cat  = srow&.attributes&.dig('category')
        sales     = srow&.attributes&.dig('sales_total').to_d
  purchases = cogs_map_ly[pid]&.attributes&.dig('cogs_total').to_d
        waste     = waste_map_ly[pid]&.attributes&.dig('waste_total').to_d
        {
          product_id: pid,
          name: name,
          brand: brand,
          category: (cat.presence || 'Uncategorized'),
          revenue: sales,
          cogs: purchases,
          profit: sales - purchases - waste
        }
      end
      @top_products_profit_last_year = prod_profit_ly.sort_by { |h| -h[:profit] }.first(10)

    # Productos más rentables (All Time)
  sales_rows_all = SaleOrderItem.joins(:sale_order, :product)
      .merge(so_scope.where(status: paid_statuses))
                  .group('products.id','products.product_name','products.brand','products.category')
                  .select("products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(#{rev_sql_str}) AS sales_total")
  waste_rows_all = Inventory.joins(:product)
           .where(status: [:marketing, :damaged, :lost, :scrap])
           .group('products.id','products.product_name','products.brand','products.category')
           .select('products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(inventories.purchase_cost) AS waste_total')
  waste_map_all = waste_rows_all.index_by { |r| r.attributes['product_id'].to_i }

  cogs_rows_all_inv = Inventory.joins(:product, :sale_order)
                               .merge(so_scope.where(status: paid_statuses))
                               .where(status: :sold)
                               .group('products.id','products.product_name','products.brand','products.category')
                               .select('products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(inventories.purchase_cost) AS cogs_total')
  if cogs_rows_all_inv.any?
    cogs_rows_all = cogs_rows_all_inv
  else
    cogs_rows_all = SaleOrderItem.joins(:sale_order, :product)
                 .merge(so_scope.where(status: paid_statuses))
                 .group('products.id','products.product_name','products.brand','products.category')
                 .select("products.id AS product_id, products.product_name AS product_name, products.brand AS brand, products.category AS category, SUM(#{cogs_sql_str}) AS cogs_total")
  end

  sales_map_all = sales_rows_all.index_by { |r| r.attributes['product_id'].to_i }
  cogs_map_all  = cogs_rows_all.index_by { |r| r.attributes['product_id'].to_i }
  all_ids_all   = (sales_map_all.keys + cogs_map_all.keys + waste_map_all.keys).uniq

      prod_profit_all = all_ids_all.map do |pid|
        srow = sales_map_all[pid]
  name = srow&.attributes&.dig('product_name')
  brand = srow&.attributes&.dig('brand')
  cat  = srow&.attributes&.dig('category')
        sales     = srow&.attributes&.dig('sales_total').to_d
  purchases = cogs_map_all[pid]&.attributes&.dig('cogs_total').to_d
        waste     = waste_map_all[pid]&.attributes&.dig('waste_total').to_d
        {
          product_id: pid,
          name: name,
          brand: brand,
          category: (cat.presence || 'Uncategorized'),
          revenue: sales,
          cogs: purchases,
          profit: sales - purchases - waste
        }
      end
      @top_products_profit_all_time = prod_profit_all.sort_by { |h| -h[:profit] }.first(10)

      # Por categoría: producto más rentable
      best_by_cat = {}
      prod_profit.each do |h|
        cat = h[:category]
        best_by_cat[cat] = h if best_by_cat[cat].nil? || h[:profit] > best_by_cat[cat][:profit]
      end
      @top_product_by_category_profit_ytd = best_by_cat.values.sort_by { |h| -h[:profit] }.first(10)

      # Por categoría: producto más rentable (Last Year)
      best_by_cat_ly = {}
      prod_profit_ly.each do |h|
        cat = h[:category]
        best_by_cat_ly[cat] = h if best_by_cat_ly[cat].nil? || h[:profit] > best_by_cat_ly[cat][:profit]
      end
      @top_product_by_category_profit_last_year = best_by_cat_ly.values.sort_by { |h| -h[:profit] }.first(10)

      # Por categoría: producto más rentable (All Time)
      best_by_cat_all = {}
      prod_profit_all.each do |h|
        cat = h[:category]
        best_by_cat_all[cat] = h if best_by_cat_all[cat].nil? || h[:profit] > best_by_cat_all[cat][:profit]
      end
      @top_product_by_category_profit_all_time = best_by_cat_all.values.sort_by { |h| -h[:profit] }.first(10)

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

    # Category profitability (profit = revenue - cogs) for current selection
    by_cat_rev = SaleOrderItem.joins(:sale_order, :product)
                               .merge(so_ytd)
                               .group('products.category')
                               .sum(Arel.sql(rev_sql))
    by_cat_cogs = SaleOrderItem.joins(:sale_order, :product)
                                .merge(so_ytd)
                                .group('products.category')
                                .sum(cogs_sql)
    cats = (by_cat_rev.keys + by_cat_cogs.keys).uniq
    cat_profit = cats.map do |c|
      rev  = by_cat_rev[c].to_d
      cogs = by_cat_cogs[c].to_d
      [(c.presence || 'Uncategorized'), rev - cogs]
    end
    cat_profit.sort_by! { |(_, p)| -p }
    top_cats_profit = cat_profit.first(8)
    @chart_category_profit = {
      categories: top_cats_profit.map(&:first),
      profit: top_cats_profit.map { |(_, p)| p }
    }

    # ============== Worst Products KPIs ==================
    # Inputs per product
    inv_stock_map    = Inventory.where(status: [:available, :in_transit]).group(:product_id).count
    inv_reserved_map = Inventory.where(status: [:reserved, :pre_reserved, :pre_sold]).group(:product_id).count
    units_sold_map   = SaleOrderItem.joins(:sale_order)
                                    .merge(so_ytd_paid)
                                    .group(:product_id)
                                    .sum(:quantity)
    product_ids = (inv_stock_map.keys + inv_reserved_map.keys + units_sold_map.keys).uniq
    products_info = Product.where(id: product_ids)
                           .pluck(:id, :product_name, :brand, :category, :selling_price, :average_purchase_cost)
                           .map { |id, name, brand, category, sp, apc| [id, { name:, brand:, category:, sp: sp.to_d, apc: apc.to_d }] }
                           .to_h

    months_in_range = months_between(@start_date, @end_date).length
    months_in_range = 1 if months_in_range <= 0

    per_product = []
    product_ids.each do |pid|
      info = products_info[pid] || { name: pid, brand: nil, category: nil, sp: 0.to_d, apc: 0.to_d }
      stock_q = inv_stock_map[pid].to_i
      res_q   = inv_reserved_map[pid].to_i
      sold_q  = units_sold_map[pid].to_i
      revenue = info[:sp].to_d * sold_q
      cogs    = info[:apc].to_d * sold_q
      margin_pct = revenue.positive? ? ((revenue - cogs) / revenue) : nil
      avg_inv_proxy = ((stock_q + res_q + sold_q).to_f / 2.0)
      rotation = avg_inv_proxy.positive? ? (sold_q.to_f / avg_inv_proxy) : nil
      avg_monthly_sales = sold_q.to_f / months_in_range
      doh = avg_monthly_sales.positive? ? ((stock_q.to_f * 30.0) / avg_monthly_sales) : (stock_q > 0 ? 1.0/0 : 0.0) # Infinity if stock>0 and no sales
      immobilized_capital = info[:apc].to_d * stock_q
      per_product << {
        product_id: pid,
        name: info[:name],
        brand: info[:brand],
        category: (info[:category].presence || 'Uncategorized'),
        stock_quantity: stock_q,
        reserved_quantity: res_q,
        units_sold: sold_q,
        revenue: revenue,
        cogs: cogs,
        margin_pct: margin_pct,
        rotation: rotation,
        doh: doh,
        avg_monthly_sales: avg_monthly_sales,
        immobilized_capital: immobilized_capital,
        avg_purchase_cost: info[:apc]
      }
    end

    # Global metrics (exclude nils/infinity as applicable)
    @worst_global_total_immobilized_capital = per_product.sum { |h| h[:immobilized_capital] }
    margin_vals = per_product.map { |h| h[:margin_pct] }.compact
    rot_vals    = per_product.map { |h| h[:rotation] }.compact
    doh_vals    = per_product.map { |h| h[:doh] }.select { |v| v.finite? }
    @worst_global_avg_margin_pct = margin_vals.any? ? (margin_vals.sum / margin_vals.size) : nil
    @worst_global_avg_rotation   = rot_vals.any? ? (rot_vals.sum / rot_vals.size) : nil
    @worst_global_avg_doh        = doh_vals.any? ? (doh_vals.sum / doh_vals.size) : nil

    # Helper: min-max normalization
    normalize = lambda do |values, value|
      vals = values.compact.map { |v| v.infinite? ? nil : v }.compact
      return 0.5 if value.nil?
      return 1.0 if value.infinite?
      return 0.5 if vals.empty?
      min = vals.min
      max = vals.max
      range = max - min
      return 0.5 if range <= 0
      [[(value - min) / range, 0.0].max, 1.0].min
    end

    margins  = per_product.map { |h| h[:margin_pct] }
    rotations = per_product.map { |h| h[:rotation] }
    dohs     = per_product.map { |h| h[:doh] }
    caps     = per_product.map { |h| h[:immobilized_capital].to_f }

    # Worst lists
    @worst_margin_products = per_product.select { |h| h[:units_sold].to_i > 0 && h[:margin_pct].present? }
                                        .sort_by { |h| h[:margin_pct] }
                                        .first(10)

    @worst_rotation_products = per_product.select { |h| h[:rotation].present? }
                                          .sort_by { |h| h[:rotation] }
                                          .first(10)

    @top_doh_products = per_product.sort_by do |h|
                          v = h[:doh]
                          v.infinite? ? Float::MAX : v
                        end.reverse.first(10)

    @top_immobilized_products = per_product.sort_by { |h| -h[:immobilized_capital].to_f }
                                           .first(10)

    # Worst score with default weights
    w1 = (params[:w1] || 0.4).to_f
    w2 = (params[:w2] || 0.2).to_f
    w3 = (params[:w3] || 0.2).to_f
    w4 = (params[:w4] || 0.2).to_f
    scored = per_product.map do |h|
      nm = normalize.call(margins, h[:margin_pct])
      nr = normalize.call(rotations, h[:rotation])
      nd = normalize.call(dohs, h[:doh])
      nc = normalize.call(caps, h[:immobilized_capital].to_f)
      worst_score = w1 * (1 - nm) + w2 * (1 - nr) + w3 * (nd) + w4 * (nc)
      h.merge(worst_score: worst_score, norm_components: { margin: nm, rotation: nr, doh: nd, capital: nc })
    end
    @worst_score_products = scored.sort_by { |h| -h[:worst_score] }.first(10)

  # === Ventas por país y por estado (México) — YTD / Last Year / All Time ===
  so_ytd_fixed = so_scope.where(order_date: now.beginning_of_year..now.end_of_day)
  ly_start_geo = now.beginning_of_year - 1.year
  ly_end_geo   = ly_start_geo.end_of_year
  so_last_year_geo = so_scope.where(order_date: ly_start_geo..ly_end_geo)

  @sales_by_country_ytd, @sales_by_mexico_states_ytd = geo_totals_for(so_ytd_fixed)
  @sales_by_country_last_year, @sales_by_mexico_states_last_year = geo_totals_for(so_last_year_geo)
  @sales_by_country_all_time, @sales_by_mexico_states_all_time = geo_totals_for(so_scope)

  # Compatibilidad con vistas previas
  @sales_by_country = @sales_by_country_ytd
  @sales_by_mexico_states = @sales_by_mexico_states_ytd
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

  # ================= Utils para geografía por heurística =================
  def geo_totals_for(scope)
    country_totals = Hash.new { |h, k| h[k] = { revenue: 0.to_d, orders: 0 } }
    mx_state_totals = Hash.new { |h, k| h[k] = { revenue: 0.to_d, orders: 0 } }
    scope.includes(:user).find_each do |so|
      addr = so.user&.address.to_s
      next if addr.blank?
      norm = normalize_text(addr)
      mx_state = detect_mex_state_in(norm)
      country = detect_country_in(norm)
      country ||= (mx_state ? 'Mexico' : nil)
      country ||= 'Desconocido'
      country_totals[country][:revenue] += so.total_order_value.to_d
      country_totals[country][:orders]  += 1
      if country == 'Mexico' && mx_state
        mx_state_totals[mx_state][:revenue] += so.total_order_value.to_d
        mx_state_totals[mx_state][:orders]  += 1
      end
    end
    total_rev_all = country_totals.values.sum { |v| v[:revenue] }
    by_country = country_totals.map do |name, agg|
      share = total_rev_all.positive? ? (agg[:revenue] / total_rev_all) : 0.to_d
      { name: name, orders: agg[:orders], revenue: agg[:revenue], share: share }
    end.sort_by { |r| -r[:revenue] }
    by_states = mx_state_totals.map { |state, agg| { state: state, orders: agg[:orders], revenue: agg[:revenue] } }
                               .sort_by { |r| -r[:revenue] }
    [by_country, by_states]
  end
  def normalize_text(text)
    I18n.transliterate(text.to_s).downcase
  end

  def detect_country_in(norm_text)
    return 'Mexico' if norm_text.include?('mexico') || norm_text.include?('méxico')
    return 'United States' if norm_text.include?('estados unidos') || norm_text.include?('eeuu') || norm_text.include?('ee. uu') || norm_text.include?('usa') || norm_text.include?('united states')
    return 'Canada' if norm_text.include?('canada')
    return 'Guatemala' if norm_text.include?('guatemala')
    return 'Spain' if norm_text.include?('espana') || norm_text.include?('españa') || norm_text.include?('spain')
    nil
  end

  def detect_mex_state_in(norm_text)
    mexican_states_synonyms.each do |canonical, tokens|
      return canonical if tokens.any? { |tok| norm_text.include?(tok) }
    end
    nil
  end

  def mexican_states_synonyms
    @mexican_states_synonyms ||= begin
      {
        'Aguascalientes' => %w[aguascalientes ags],
        'Baja California' => ['baja california', 'bc'],
        'Baja California Sur' => ['baja california sur', 'bcs'],
        'Campeche' => %w[campeche camp],
        'Coahuila' => ['coahuila', 'coah', 'coahuila de zaragoza'],
        'Colima' => ['colima', 'col.'],
        'Chiapas' => %w[chiapas chis],
        'Chihuahua' => %w[chihuahua chih],
        'Ciudad de México' => ['ciudad de mexico', 'cdmx', 'df', 'd.f.', 'mexico city'],
        'Durango' => %w[durango dgo],
        'Guanajuato' => %w[guanajuato gto],
        'Guerrero' => %w[guerrero gro],
        'Hidalgo' => %w[hidalgo hgo],
        'Jalisco' => %w[jalisco jal],
        'Estado de México' => ['estado de mexico', 'edomex', 'mex.','mexico state'],
        'Michoacán' => ['michoacan', 'michoacán', 'mich'],
        'Morelos' => %w[morelos mor],
        'Nayarit' => %w[nayarit nay],
        'Nuevo León' => ['nuevo leon', 'nl', 'n.l.'],
        'Oaxaca' => %w[oaxaca oax],
        'Puebla' => %w[puebla pue],
        'Querétaro' => ['queretaro', 'querétaro', 'qro'],
        'Quintana Roo' => ['quintana roo', 'q roo', 'qroo'],
        'San Luis Potosí' => ['san luis potosi', 'slp'],
        'Sinaloa' => %w[sinaloa sin],
        'Sonora' => %w[sonora son],
        'Tabasco' => %w[tabasco tab],
        'Tamaulipas' => ['tamaulipas', 'tmps', 'tamps'],
        'Tlaxcala' => %w[tlaxcala tlax],
        'Veracruz' => ['veracruz', 'ver', 'veracruz de ignacio de la llave'],
        'Yucatán' => ['yucatan', 'yucatan', 'yuc'],
        'Zacatecas' => %w[zacatecas zac]
      }
    end
  end
end
