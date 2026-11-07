require 'rails_helper'

RSpec.describe Finance::MonthlyStatement do
  let(:product) { create(:product, skip_seed_inventory: true) }

  around { |example| travel_to(Time.zone.local(2026, 6, 15, 12)) { example.run } }

  def statement(year: 2026)
    described_class.new(year: year).call
  end

  def make_order(total:, status: 'Delivered', order_date: Date.new(2026, 1, 5))
    order = create(:sale_order)
    order.update_columns(total_order_value: total, status: status, order_date: order_date)
    order
  end

  def line(order, price:, cost:)
    item = create(:sale_order_item, sale_order: order, product: product, quantity: 1, unit_cost: price,
                                    unit_final_price: price, total_line_cost: price)
    item.update_columns(total_line_cost: price, unit_acquisition_cost: cost)
    item
  end

  def pay(order, amount, paid_at, status: 'Completed', refunded_at: nil)
    payment = create(:payment, sale_order: order, amount: amount)
    payment.update_columns(paid_at: paid_at, status: status, refunded_at: refunded_at)
    payment
  end

  # Venta concluida el día `on` por `price` con costo `cost`.
  def sale(price:, cost:, on:)
    order = make_order(total: price, order_date: on)
    line(order, price: price, cost: cost)
    order.update_columns(total_order_value: price) # el callback de la línea recalcula el total
    pay(order, price, on)
    order
  end

  def purchase_order(order_date:, total_cost_mxn:)
    po = create(:purchase_order)
    po.update_columns(order_date: order_date, total_cost_mxn: total_cost_mxn, total_order_cost: 0, status: 'Pending')
    po
  end

  def piece(cost:, created_at:)
    inv = create(:inventory, product: product, purchase_cost: cost)
    inv.update_columns(created_at: created_at)
    inv
  end

  it 'año: 12 periodos, junio :current, julio..dic :future con nil' do
    result = statement

    expect(result.periods.size).to eq(12)
    expect(result.periods.map(&:label)).to eq(%w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic])
    expect(result.periods.map(&:state)).to eq([:closed] * 5 + [:current] + [:future] * 6)
    expect(result.periods[1]).to have_attributes(starts_on: Date.new(2026, 2, 1), ends_on: Date.new(2026, 2, 28))
    expect(result.rows.keys).to eq(%i[sales sales_count discounts sale_refunds cogs profit margin
                                      profit_cumulative cash_in purchases refunds cashflow
                                      cashflow_cumulative advances inventory])
    result.rows.each_value do |values|
      expect(values.size).to eq(12)
      expect(values[6..]).to all(be_nil)
    end
    expect(result.rows[:sales][5]).to eq(0)
    expect(result.deltas[:profit][6..]).to all(be_nil)
    expect(result.deltas[:cashflow][6..]).to all(be_nil)
    expect(result).to have_attributes(year: 2026, history: false)
  end

  it 'utilidad, margen y flujo del mes' do
    sale(price: 100, cost: 60, on: Date.new(2026, 3, 10))
    purchase_order(order_date: Date.new(2026, 3, 2), total_cost_mxn: 500)

    rows = statement.rows
    expect(rows[:sales][2]).to eq(100)
    expect(rows[:sales_count][2]).to eq(1)
    expect(rows[:cogs][2]).to eq(60)
    expect(rows[:profit][2]).to eq(40)
    expect(rows[:profit][2]).to be_a(BigDecimal)
    expect(rows[:margin][2]).to eq(BigDecimal('0.4'))
    expect(rows[:cash_in][2]).to eq(100)
    expect(rows[:purchases][2]).to eq(500)
    expect(rows[:cashflow][2]).to eq(100 - 500)
    expect(rows[:margin][1]).to be_nil
  end

  it 'acumulados incluyen años anteriores' do
    sale(price: 25, cost: 0, on: Date.new(2025, 5, 10))
    sale(price: 40, cost: 0, on: Date.new(2026, 3, 10))

    result = statement
    expect(result.rows[:profit_cumulative][0]).to eq(25)
    expect(result.rows[:profit_cumulative][2]).to eq(65)
    expect(result.rows[:profit_cumulative][5]).to eq(65)
    expect(result.rows[:cashflow_cumulative][0]).to eq(25)
    expect(result.rows[:cashflow_cumulative][2]).to eq(65)
    expect(result.first_year).to eq(2025)
  end

  it 'delta de enero compara contra diciembre del año anterior' do
    sale(price: 30, cost: 0, on: Date.new(2025, 12, 20))
    sale(price: 10, cost: 0, on: Date.new(2026, 1, 20))

    deltas = statement.deltas
    expect(deltas[:profit][0]).to eq(-20)
    expect(deltas[:cashflow][0]).to eq(-20)
    expect(deltas[:profit][1]).to eq(-10)
    expect(deltas[:profit][0]).to be_a(BigDecimal)
  end

  it 'totales: suman flujos y toman saldos del último periodo no futuro' do
    sale(price: 100, cost: 60, on: Date.new(2026, 3, 10))
    sale(price: 50, cost: 20, on: Date.new(2026, 5, 10))
    purchase_order(order_date: Date.new(2026, 3, 2), total_cost_mxn: 500)
    advance = make_order(total: 100, status: 'Pending')
    pay(advance, 20, Date.new(2026, 4, 3))
    piece(cost: 7, created_at: Time.zone.local(2026, 2, 10, 12))
    piece(cost: 3, created_at: Time.zone.local(2026, 6, 20, 12)) # después de hoy: no está en el saldo de junio

    result = statement
    totals = result.totals
    expect(totals).to include(sales: 150, sales_count: 2, cogs: 80, profit: 70, cash_in: 170, purchases: 510)
    expect(totals[:sales_count]).to be_a(Integer)
    expect(totals[:margin]).to eq(BigDecimal('70') / BigDecimal('150'))
    expect(totals[:cashflow]).to eq(170 - 510)
    expect(totals[:profit_cumulative]).to eq(70)
    expect(totals[:cashflow_cumulative]).to eq(-340)
    expect(result.rows[:inventory][5]).to eq(7)
    expect(totals[:inventory]).to eq(7)
    expect(result.rows[:advances][3]).to eq(20)
    expect(totals[:advances]).to eq(20)
  end

  it 'histórico: una columna por año desde first_year' do
    sale(price: 30, cost: 10, on: Date.new(2024, 8, 1))
    sale(price: 50, cost: 10, on: Date.new(2026, 2, 1))

    result = statement(year: nil)
    expect(result.periods.map(&:label)).to eq(%w[2024 2025 2026])
    expect(result.periods.map(&:state)).to eq(%i[closed closed current])
    expect(result.periods.first).to have_attributes(starts_on: Date.new(2024, 1, 1), ends_on: Date.new(2024, 12, 31))
    expect(result).to have_attributes(year: nil, history: true, first_year: 2024)
    expect(result.rows[:profit]).to eq([20, 0, 40])
    expect(result.rows[:profit_cumulative]).to eq([20, 20, 60])
    expect(result.deltas[:profit]).to eq([20, -20, 40])
    expect(result.totals[:profit]).to eq(60)
    expect(result.totals[:profit_cumulative]).to eq(60)
  end

  it 'base vacía: año en curso con ceros y margen nil' do
    result = statement

    expect(described_class.first_operation_on).to be_nil
    expect(result.first_year).to eq(2026)
    expect(result.rows[:sales][0..5]).to all(eq(0))
    expect(result.rows[:inventory][0..5]).to all(eq(0))
    expect(result.rows[:margin]).to all(be_nil)
    expect(result.totals).to include(sales: 0, profit: 0, margin: nil, inventory: 0)

    history = statement(year: nil)
    expect(history.periods.map(&:label)).to eq(%w[2026])
  end

  it 'mes con reembolso y sin ventas: margen nil y utilidad negativa' do
    order = make_order(total: 100, order_date: Date.new(2026, 2, 5))
    line(order, price: 100, cost: 60)
    order.update_columns(total_order_value: 100)
    pay(order, 70, Date.new(2026, 2, 10))
    pay(order, 30, Date.new(2026, 2, 12), status: 'Refunded', refunded_at: Date.new(2026, 4, 15))

    rows = statement.rows
    expect(rows[:profit][3]).to eq(-30)
    expect(rows[:margin][3]).to be_nil
    expect(rows[:cashflow][3]).to eq(-30)
  end

  describe '.first_operation_on' do
    it 'toma el mínimo entre ventas, pagos, compras no canceladas y altas manuales' do
      sale(price: 10, cost: 0, on: Date.new(2025, 3, 1))
      canceled = purchase_order(order_date: Date.new(2023, 1, 1), total_cost_mxn: 10)
      canceled.update_columns(status: 'Canceled')
      expect(described_class.first_operation_on).to eq(Date.new(2025, 3, 1))

      piece(cost: 5, created_at: Time.zone.local(2024, 7, 1, 12))
      expect(described_class.first_operation_on).to eq(Date.new(2024, 7, 1))

      purchase_order(order_date: Date.new(2024, 2, 1), total_cost_mxn: 10)
      expect(described_class.first_operation_on).to eq(Date.new(2024, 2, 1))
    end
  end
end
