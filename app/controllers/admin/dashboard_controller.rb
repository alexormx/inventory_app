# frozen_string_literal: true

module Admin
  # Refactored Dashboard Controller using service objects for cleaner architecture.
  # Original controller had ~1400 lines with methods defined inside index action.
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    layout 'admin'

    # SQL constants for revenue and COGS calculations (shared across controller)
    REV_SQL = Dashboard::Metrics::REV_SQL
    # COGS uses product's average_purchase_cost (the actual acquisition cost, not sale_order_items.unit_cost which incorrectly stores the sale price)
    COGS_SQL = Dashboard::Metrics::COGS_SQL
    UNITS_SQL = Dashboard::Metrics::UNITS_SQL
    PAID_STATUSES = Dashboard::Metrics::SALE_STATUSES

    # Main dashboard view with KPIs, charts, and rankings
    def index
      setup_date_filters
      setup_base_scopes
      load_kpis
      load_comparisons
      load_alerts_and_activity
      load_status_counts
      load_chart_data
      load_worst_products
      load_geo_sales
    end

    # Turbo Frame: Top Sellers by period
    def sellers
      period = params[:period].presence || 'ytd'
      @rows = build_sellers_data(period_scope_for(period).where(status: PAID_STATUSES))
      @period = period

      respond_to { |format| format.html { render layout: false } }
    end

    # Turbo Frame: Most Profitable Products by period
    def profitable
      period = params[:period].presence || 'ytd'
      @rows = build_profitable_data(period_scope_for(period).where(status: PAID_STATUSES))
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
      @period_badge_label = build_period_badge_label
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
      # Pending y Returned no son venta realizada (ver SaleOrder::ACTIVE_SALE_STATUSES):
      # los KPI de venta usan este scope para cuadrar con los rankings.
      @so_sales = @so_scope.where(status: PAID_STATUSES)
      @po_ytd = @po_scope.where(order_date: @range)
      # Sin filtro de estado: la tasa de cancelación necesita las canceladas en
      # el denominador y en el numerador.
      @so_ytd_all = SaleOrder.where(order_date: @range)
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
      @gross_sales_ytd = Dashboard::Metrics.revenue_total(@so_ytd_paid)
      @order_discount_ytd = Dashboard::Metrics.order_discount_total(@so_ytd_paid)
      @sales_ytd = @gross_sales_ytd - @order_discount_ytd
      @purchases_ytd = purchase_total_for(@po_ytd) + manual_purchase_total_for(@range)

      @cash_in_ytd = completed_income_total_for(@range)
      @cash_out_ytd = @purchases_ytd
      @cashflow_ytd = @cash_in_ytd - @cash_out_ytd

      @cogs_ytd = Dashboard::Metrics.cogs_total(@so_ytd_paid)
      @profit_ytd = @sales_ytd - @cogs_ytd
      @margin_ytd = @sales_ytd.positive? ? (@profit_ytd / @sales_ytd) : 0.to_d

      @orders_count_ytd = @so_ytd_paid.count
      @po_count_ytd = @po_ytd.count
      @active_customers_ytd = @so_ytd_paid.select(:user_id).distinct.count
      @inventory_total_value = Product.sum(:current_inventory_value).to_d

      @so_items_qty_ytd = SaleOrderItem.joins(:sale_order).merge(@so_ytd_paid).sum(:quantity).to_i

      @purchases_total_mxn = purchase_total_for(@po_scope) + manual_purchase_total_for

      @avg_ticket_ytd = @orders_count_ytd.positive? ? (@sales_ytd / @orders_count_ytd) : 0.to_d
      # Unidades por transacción: separa "vendemos más caro" de "vendemos más
      # piezas" cuando sube el ticket promedio.
      @units_per_order_ytd = @orders_count_ytd.positive? ? (@so_items_qty_ytd.to_d / @orders_count_ytd) : nil

      # Se filtra por last_visited_at para que numerador y denominador cubran el
      # mismo periodo; antes eran pedidos del rango sobre visitas de todo el
      # historial, así que la tasa solo podía bajar con el tiempo.
      @visits_total = begin
        VisitorLog.where(last_visited_at: @range).sum(:visit_count)
      rescue StandardError
        nil
      end
      @conversion_rate_ytd = @visits_total.to_i.positive? ? (@orders_count_ytd.to_d / @visits_total.to_d) : nil

      @lost_orders = Dashboard::Metrics.lost_orders_stats(@so_ytd_all)

      load_customer_metrics
      load_critical_stock
      load_inventory_turnover
      load_balance_summaries
      load_all_time_totals
      load_receivables_aging
      load_whatsapp_funnel
    end

    def load_receivables_aging
      @receivables_aging = Dashboard::ReceivablesAgingBuilder.new(
        net_revenue: @sales_ytd,
        period_days: (@end_date.to_date - @start_date.to_date).to_i + 1
      ).call
    end

    def load_whatsapp_funnel
      @whatsapp_funnel = Dashboard::WhatsappFunnelBuilder.new(@range).call
    end

    def load_customer_metrics
      active_user_ids = @so_ytd_paid.where.not(user_id: nil).distinct.pluck(:user_id)
      historical_order_counts = @so_sales.where(user_id: active_user_ids).group(:user_id).count

      @new_customers_ytd = active_user_ids.count { |user_id| historical_order_counts[user_id].to_i <= 1 }
      @recurring_customers_ytd = active_user_ids.count { |user_id| historical_order_counts[user_id].to_i > 1 }
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

    def load_balance_summaries
      month_range = @now.beginning_of_month.to_date..@now.end_of_day
      year_range = @now.beginning_of_year.to_date..@now.end_of_day

      @collected_income_month_mxn = completed_income_total_for(month_range)
      @purchases_month_mxn = purchase_total_for(@po_scope.where(order_date: month_range)) + manual_purchase_total_for(month_range)
      @net_balance_month_mxn = @collected_income_month_mxn - @purchases_month_mxn

      @collected_income_year_mxn = completed_income_total_for(year_range)
      @purchases_year_mxn = purchase_total_for(@po_scope.where(order_date: year_range)) + manual_purchase_total_for(year_range)
      @net_balance_year_mxn = @collected_income_year_mxn - @purchases_year_mxn
    end

    def load_all_time_totals
      rev_sql_arel = Arel.sql(REV_SQL)
      @sales_total_mxn = SaleOrderItem.joins(:sale_order).merge(@so_sales).sum(rev_sql_arel).to_d
      @collected_income_total_mxn = completed_income_total_for
      @historical_net_total_mxn = @collected_income_total_mxn - @purchases_total_mxn
    end

    # === Year-over-Year Comparisons ===
    def load_comparisons
      range_prev_start = @start_date.prev_year
      range_prev_end = @end_date.prev_year
      so_prev_range = @so_sales.where(order_date: range_prev_start..range_prev_end)
      po_prev_range = @po_scope.where(order_date: range_prev_start..range_prev_end)

      @sales_prev = Dashboard::Metrics.net_revenue_total(so_prev_range)
      @cogs_prev = Dashboard::Metrics.cogs_total(so_prev_range)
      @profit_prev = @sales_prev - @cogs_prev
      @margin_prev = @sales_prev.positive? ? (@profit_prev / @sales_prev) : 0.to_d
      @orders_prev = so_prev_range.count
      @po_count_prev = po_prev_range.count
      @active_customers_prev = so_prev_range.select(:user_id).distinct.count

      @cash_in_prev = completed_income_total_for(range_prev_start..range_prev_end)
      @cash_out_prev = purchase_total_for(po_prev_range) + manual_purchase_total_for(range_prev_start..range_prev_end)
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

    def build_period_badge_label
      case @range_key
      when 'last_30'
        'Últimos 30 días'
      when 'last_90'
        'Últimos 90 días'
      when 'custom'
        "Personalizado #{format_badge_date(@start_date)}–#{format_badge_date(@end_date)}"
      else
        "YTD #{@now.year}"
      end
    end

    def format_badge_date(value)
      value.to_date.strftime('%d/%m/%Y')
    end

    def completed_income_total_for(date_range = nil)
      scope = Payment.joins(:sale_order).merge(@so_scope).where(status: 'Completed')
      scope = scope.where(paid_at: date_range) if date_range.present?
      scope.sum(:amount).to_d
    end

    def grouped_completed_income_by(date_range, group_expr)
      Payment.joins(:sale_order)
             .merge(@so_scope)
             .where(status: 'Completed', paid_at: date_range)
             .group(Arel.sql(group_expr))
             .sum(:amount)
    end

    def purchase_total_for(scope)
      total = scope.sum(:total_cost_mxn).to_d
      total = scope.sum(:total_order_cost).to_d if total.zero?
      total
    end

    # Inventarios agregados manualmente (sin PurchaseOrder), p.ej. coleccionables
    # vía quick_add. Se incluyen en los totales de compras del dashboard.
    def manual_purchase_scope
      Inventory.where(purchase_order_item_id: nil).where('purchase_cost > 0')
    end

    def manual_purchase_total_for(date_range = nil)
      scope = manual_purchase_scope
      scope = scope.where(created_at: date_range) if date_range
      scope.sum(:purchase_cost).to_d
    end

    def manual_purchase_grouped_by_month(date_range)
      expr = month_group_expr('inventories', 'created_at')
      manual_purchase_scope.where(created_at: date_range).group(Arel.sql(expr)).sum(:purchase_cost)
    end

    # === Alerts & Recent Activity ===
    def load_alerts_and_activity
      load_alerts
      load_recent_activity
    end

    def load_alerts
      @alerts = []

      # Órdenes que requieren atención manual (sin pagar >30 días, pagadas de más, inconsistentes).
      order_alerts = SaleOrders::Alerts.counts.values.sum
      if order_alerts.positive?
        @alerts << {
          type: 'warning',
          icon: 'fa-triangle-exclamation',
          message: "#{order_alerts} órdenes requieren atención",
          link: admin_order_alerts_path,
          link_text: 'Ver alertas'
        }
      end

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
      @last_purchase_received = PurchaseOrder.where(status: 'Delivered').order(updated_at: :desc).first

      # Próximo envío (orden confirmada más antigua)
      @next_shipment = SaleOrder.where(status: 'Confirmed').order(order_date: :asc).first
    rescue StandardError => e
      Rails.logger.error "Dashboard activity error: #{e.message}"
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

    # === Status Counts ===
    def load_status_counts
      @so_status_counts = @so_scope.group(:status).count
      @po_status_counts = @po_scope.group(:status).count

      # Pie chart data for order status donut charts
      so_colors = { 'Pending' => '#94a3b8', 'Confirmed' => '#3b82f6', 'Preparing' => '#8b5cf6',
                    'In Transit' => '#06b6d4', 'Delivered' => '#10b981', 'Canceled' => '#ef4444',
                    'Returned' => '#f59e0b' }
      @so_status_pie = @so_status_counts.map { |s, c| { name: s, value: c, itemStyle: { color: so_colors[s] || '#64748b' } } }

      po_colors = { 'Pending' => '#94a3b8', 'In Transit' => '#f59e0b', 'Delivered' => '#10b981',
                    'Canceled' => '#ef4444' }
      @po_status_pie = @po_status_counts.map { |s, c| { name: s, value: c, itemStyle: { color: po_colors[s] || '#64748b' } } }
    end

    # === Chart Data ===
    def load_chart_data
      trend_start = (@end_date - 11.months).beginning_of_month
      trend_range = trend_start..@end_date
      month_key_expr = month_group_expr('sale_orders', 'order_date')
      rev_sql_arel = Arel.sql(REV_SQL)
      cogs_sql_arel = Arel.sql(COGS_SQL)

      trend_rev = SaleOrderItem.joins(:sale_order)
                               .merge(@so_sales.where(order_date: trend_range))
                               .group(Arel.sql(month_key_expr))
                               .sum(rev_sql_arel)
      trend_cogs = SaleOrderItem.joins(:sale_order, :product)
                                .merge(@so_sales.where(order_date: trend_range))
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
      month_key_expr_payments = month_group_expr('payments', 'paid_at')

      inflow_map = grouped_completed_income_by(trend_range, month_key_expr_payments)

      outflow_po_costs = @po_scope.where(order_date: trend_range)
      outflow_map = outflow_po_costs.group(Arel.sql(month_key_expr_po)).sum(:total_cost_mxn)
      outflow_map = outflow_po_costs.group(Arel.sql(month_key_expr_po)).sum(:total_order_cost) if outflow_map.values.all? { |v| v.to_d.zero? }

      inflow_norm = inflow_map.transform_keys { |k| normalize_month_key(k) }
      outflow_norm = outflow_map.transform_keys { |k| normalize_month_key(k) }
      manual_norm = manual_purchase_grouped_by_month(trend_range).transform_keys { |k| normalize_month_key(k) }
      manual_norm.each { |k, v| outflow_norm[k] = (outflow_norm[k] || 0).to_d + v.to_d }

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

      month_key_expr_po = month_group_expr('purchase_orders', 'order_date')
      month_key_expr_payments = month_group_expr('payments', 'paid_at')

      # Ingresos (ventas pagadas) por mes - año actual
      current_year_start = Date.new(current_year, 1, 1)
      current_year_end = Date.new(current_year, 12, 31).end_of_day
      inflow_current = Payment.joins(:sale_order)
              .merge(@so_scope)
              .where(status: 'Completed', paid_at: current_year_start..current_year_end)
              .group(Arel.sql(month_key_expr_payments))
              .sum(:amount)
                                    .transform_keys { |k| normalize_month_key(k) }

      # Egresos (compras) por mes - año actual
      outflow_current_scope = @po_scope.where(order_date: current_year_start..current_year_end)
      outflow_current = outflow_current_scope.group(Arel.sql(month_key_expr_po)).sum(:total_cost_mxn)
      outflow_current = outflow_current_scope.group(Arel.sql(month_key_expr_po)).sum(:total_order_cost) if outflow_current.values.all? { |v| v.to_d.zero? }
      outflow_current = outflow_current.transform_keys { |k| normalize_month_key(k) }
      manual_current = manual_purchase_grouped_by_month(current_year_start..current_year_end).transform_keys { |k| normalize_month_key(k) }
      manual_current.each { |k, v| outflow_current[k] = (outflow_current[k] || 0).to_d + v.to_d }

      # Ingresos (ventas pagadas) por mes - año anterior
      prev_year_start = Date.new(prev_year, 1, 1)
      prev_year_end = Date.new(prev_year, 12, 31).end_of_day
      inflow_prev = Payment.joins(:sale_order)
               .merge(@so_scope)
               .where(status: 'Completed', paid_at: prev_year_start..prev_year_end)
               .group(Arel.sql(month_key_expr_payments))
               .sum(:amount)
                                 .transform_keys { |k| normalize_month_key(k) }

      # Egresos (compras) por mes - año anterior
      outflow_prev_scope = @po_scope.where(order_date: prev_year_start..prev_year_end)
      outflow_prev = outflow_prev_scope.group(Arel.sql(month_key_expr_po)).sum(:total_cost_mxn)
      outflow_prev = outflow_prev_scope.group(Arel.sql(month_key_expr_po)).sum(:total_order_cost) if outflow_prev.values.all? { |v| v.to_d.zero? }
      outflow_prev = outflow_prev.transform_keys { |k| normalize_month_key(k) }
      manual_prev = manual_purchase_grouped_by_month(prev_year_start..prev_year_end).transform_keys { |k| normalize_month_key(k) }
      manual_prev.each { |k, v| outflow_prev[k] = (outflow_prev[k] || 0).to_d + v.to_d }

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
      result = analytics_builder.category_charts_bundle
      @chart_monthly_by_category = result[:monthly_by_category]
      @chart_brand_profit = result[:brand_profit]
      @chart_category_profit = result[:category_profit]
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

    def build_categories_data(scope, metric)
      Dashboard::Metrics.category_rows(scope, metric: metric, limit: 10)
    end

    def build_customers_data(scope, metric)
      rankings_builder.customers_rows(scope: scope, metric: metric, limit: 10)
    end

    def rankings_builder
      @rankings_builder ||= ::Dashboard::RankingsBuilder.new(
        now: @now,
        so_scope: @so_scope,
        so_ytd: @so_ytd,
        so_ytd_paid: @so_ytd_paid,
        start_date: @start_date,
        end_date: @end_date
      )
    end

    def analytics_builder
      @analytics_builder ||= ::Dashboard::AnalyticsBuilder.new(
        so_ytd: @so_ytd,
        start_date: @start_date,
        end_date: @end_date
      )
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
