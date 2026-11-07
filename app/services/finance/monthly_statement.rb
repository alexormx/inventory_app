# frozen_string_literal: true

module Finance
  # Estado de resultados y flujo por mes de un año, o por año en la vista
  # histórica (year: nil). Compone PeriodFlows y ClosingBalances; ver "La
  # página" y "Filas" del spec de finanzas mensual.
  #
  #   Finance::MonthlyStatement.new(year: 2026).call  # => Result
  #   Finance::MonthlyStatement.new(year: nil).call   # una columna por año
  class MonthlyStatement
    ROW_LABELS = {
      sales: 'Ventas concluidas', sales_count: 'Órdenes concluidas', discounts: 'Descuentos',
      sale_refunds: 'Reembolsos de ventas', cogs: 'Costo de lo vendido', profit: 'Utilidad del mes',
      margin: 'Margen', profit_cumulative: 'Utilidad acumulada histórica',
      cash_in: 'Cobros (incl. anticipos)', purchases: 'Compras y altas manuales', refunds: 'Reembolsos',
      cashflow: 'Flujo del mes', cashflow_cumulative: 'Flujo acumulado histórico',
      advances: 'Anticipos por entregar', inventory: 'Inventario a costo'
    }.freeze
    ROW_KEYS = ROW_LABELS.keys.freeze
    HISTORY_LABELS = { profit: 'Utilidad del año', cashflow: 'Flujo del año' }.freeze

    MONTH_LABELS = %w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic].freeze
    FLOW_KEYS = PeriodFlows::KEYS
    # Filas que se suman en el total; el resto (margen, acumulados, saldos) no.
    SUMMED_KEYS = (FLOW_KEYS + %i[profit cashflow]).freeze
    LAST_VALUE_KEYS = %i[profit_cumulative cashflow_cumulative advances inventory].freeze

    Period = Data.define(:starts_on, :ends_on, :label, :state) do
      def future? = state == :future
      def current? = state == :current
    end

    Result = Data.define(:periods, :rows, :deltas, :totals, :year, :first_year, :history)

    # Etiqueta de una fila; en la vista histórica las filas del periodo dicen "del año".
    def self.row_label(key, history:)
      (history && HISTORY_LABELS[key]) || ROW_LABELS.fetch(key)
    end

    # Primera fecha con alguna operación: conclusión de venta, pago recibido,
    # orden de compra no cancelada o alta manual de inventario.
    def self.first_operation_on
      conn = ActiveRecord::Base.connection
      received = RECEIVED_PAYMENT_STATUSES.map { |s| conn.quote(s) }.join(', ')
      created_on = Finance.local_date_sql('inventories.created_at')
      sql = <<~SQL.squish
        SELECT MIN(d) FROM (
          SELECT MIN(rec.concluded_on) AS d FROM (#{SaleRecognition.sql}) rec
          UNION ALL
          SELECT MIN(payments.paid_at) FROM payments
          WHERE payments.status IN (#{received}) AND payments.paid_at IS NOT NULL
          UNION ALL
          SELECT MIN(purchase_orders.order_date) FROM purchase_orders
          WHERE purchase_orders.status <> 'Canceled'
          UNION ALL
          SELECT MIN(#{created_on}) FROM inventories
          WHERE inventories.purchase_order_id IS NULL
            AND inventories.purchase_order_item_id IS NULL
            AND inventories.purchase_cost > 0
        ) firsts
      SQL
      value = conn.select_value(sql)
      value.is_a?(String) ? Date.parse(value) : value
    end

    def initialize(year:, today: Time.zone.today)
      @year = year
      @today = today
      @history = year.nil?
      @grain = @history ? :year : :month
    end

    def call
      first_operation_on = self.class.first_operation_on
      first_year = first_operation_on&.year || @today.year
      periods = build_periods(first_year)
      flows = period_flows(periods)
      opening = opening_flows(first_operation_on, periods.first.starts_on)
      balances = closing_balances(periods)

      rows = build_rows(periods, flows, opening, balances)
      Result.new(
        periods: periods,
        rows: rows,
        deltas: build_deltas(periods, flows, rows),
        totals: build_totals(periods, rows),
        year: @year,
        first_year: first_year,
        history: @history
      )
    end

    private

    def build_periods(first_year)
      if @history
        (first_year..@today.year).map do |y|
          period(Date.new(y, 1, 1), Date.new(y, 12, 31), y.to_s)
        end
      else
        (1..12).map do |m|
          starts_on = Date.new(@year, m, 1)
          period(starts_on, starts_on.end_of_month, MONTH_LABELS[m - 1])
        end
      end
    end

    def period(starts_on, ends_on, label)
      state = if ends_on < @today
                :closed
              elsif starts_on <= @today
                :current
              else
                :future
              end
      Period.new(starts_on: starts_on, ends_on: ends_on, label: label, state: state)
    end

    # Flujos del rango más el periodo anterior, para el delta de la primera columna.
    def period_flows(periods)
      from = previous_start(periods.first.starts_on)
      PeriodFlows.new(range: from..periods.last.ends_on, grain: @grain).call
    end

    def previous_start(starts_on)
      @history ? starts_on.prev_year : starts_on.prev_month
    end

    # Suma de flujos de todo lo anterior al rango, en una sola consulta anual.
    def opening_flows(first_operation_on, range_start)
      return empty_flows if first_operation_on.nil? || first_operation_on >= range_start

      PeriodFlows.new(range: first_operation_on...range_start, grain: :year).call.values
                 .each_with_object(empty_flows) { |bucket, sum| FLOW_KEYS.each { |k| sum[k] += bucket[k] } }
    end

    # Saldos sólo al cierre de los periodos no futuros; el actual, a hoy.
    def closing_balances(periods)
      ClosingBalances.new(dates: periods.reject(&:future?).map { |p| balance_date(p) }).call
    end

    def balance_date(period)
      period.current? ? @today : period.ends_on
    end

    def build_rows(periods, flows, opening, balances)
      rows = ROW_KEYS.index_with { [] }
      profit_cumulative = profit(opening)
      cashflow_cumulative = cashflow(opening)

      periods.each do |period|
        if period.future?
          ROW_KEYS.each { |key| rows[key] << nil }
          next
        end

        bucket = flows.fetch(period.starts_on) { empty_flows }
        profit_cumulative += profit(bucket)
        cashflow_cumulative += cashflow(bucket)
        balance = balances.fetch(balance_date(period))
        values = bucket.merge(
          profit: profit(bucket), margin: margin(bucket), profit_cumulative: profit_cumulative,
          cashflow: cashflow(bucket), cashflow_cumulative: cashflow_cumulative,
          advances: balance[:advances], inventory: balance[:inventory]
        )
        ROW_KEYS.each { |key| rows[key] << values.fetch(key) }
      end
      rows
    end

    def build_deltas(periods, flows, rows)
      previous = flows.fetch(previous_start(periods.first.starts_on)) { empty_flows }
      prev_profit = profit(previous)
      prev_cashflow = cashflow(previous)

      deltas = { profit: [], cashflow: [] }
      periods.each_with_index do |period, i|
        if period.future?
          deltas[:profit] << nil
          deltas[:cashflow] << nil
          next
        end
        deltas[:profit] << (rows[:profit][i] - prev_profit)
        deltas[:cashflow] << (rows[:cashflow][i] - prev_cashflow)
        prev_profit = rows[:profit][i]
        prev_cashflow = rows[:cashflow][i]
      end
      deltas
    end

    def build_totals(periods, rows)
      indexes = periods.each_index.reject { |i| periods[i].future? }
      return ROW_KEYS.index_with { nil } if indexes.empty?

      totals = SUMMED_KEYS.index_with { |key| indexes.sum { |i| rows[key][i] } }
      LAST_VALUE_KEYS.each { |key| totals[key] = rows[key][indexes.last] }
      totals[:margin] = margin(totals)
      ROW_KEYS.index_with { |key| totals[key] }
    end

    def profit(bucket)
      bucket[:sales] - bucket[:discounts] - bucket[:sale_refunds] - bucket[:cogs]
    end

    def cashflow(bucket)
      bucket[:cash_in] - bucket[:purchases] - bucket[:refunds]
    end

    def margin(bucket)
      net_sales = bucket[:sales] - bucket[:discounts]
      return nil unless net_sales.positive?

      profit(bucket) / net_sales
    end

    def empty_flows
      FLOW_KEYS.index_with { |key| PeriodFlows::INTEGER_KEYS.include?(key) ? 0 : BigDecimal('0') }
    end
  end
end
