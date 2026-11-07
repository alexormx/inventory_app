require 'rails_helper'

RSpec.describe Finance::PeriodFlows do
  let(:range) { Date.new(2026, 1, 1)..Date.new(2026, 12, 31) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  def flows(grain: :month)
    described_class.new(range: range, grain: grain).call
  end

  def make_order(total: 100, discount: nil, status: 'Delivered', order_date: Date.new(2026, 3, 5))
    order = create(:sale_order)
    order.update_columns(total_order_value: total, discount: discount, status: status, order_date: order_date)
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

  def purchase_order(order_date:, total_cost_mxn:, total_order_cost: 0, status: 'Pending')
    po = create(:purchase_order)
    po.update_columns(order_date: order_date, total_cost_mxn: total_cost_mxn, total_order_cost: total_order_cost,
                      status: status)
    po
  end

  it 'cuenta la venta en el mes de conclusión, no en order_date' do
    order = make_order
    line(order, price: 100, cost: 60)
    pay(order, 40, Date.new(2026, 3, 10))
    pay(order, 60, Date.new(2026, 6, 2))

    result = flows
    expect(result[Date.new(2026, 3, 1)][:cash_in]).to eq(40)
    expect(result[Date.new(2026, 3, 1)][:sales].to_d).to eq(0)
    expect(result[Date.new(2026, 6, 1)]).to include(sales: 100, cogs: 60, cash_in: 60, sales_count: 1)
    expect(result[Date.new(2026, 6, 1)][:sales]).to be_a(BigDecimal)
    expect(result[Date.new(2026, 6, 1)][:sales_count]).to be_a(Integer)
  end

  it 'descuento de orden no se multiplica por líneas' do
    order = make_order(total: 90, discount: 10)
    line(order, price: 50, cost: 20)
    line(order, price: 50, cost: 20)
    pay(order, 90, Date.new(2026, 3, 10))

    month = flows[Date.new(2026, 3, 1)]
    expect(month).to include(sales: 100, discounts: 10, cogs: 40, sales_count: 1)
  end

  it 'reembolso resta en el mes del reembolso y no toca el original' do
    order = make_order
    line(order, price: 100, cost: 60)
    pay(order, 70, Date.new(2026, 3, 10))
    pay(order, 30, Date.new(2026, 3, 12), status: 'Refunded', refunded_at: Date.new(2026, 5, 15))

    result = flows
    expect(result[Date.new(2026, 3, 1)]).to include(sales: 100, cash_in: 100, sale_refunds: 0, refunds: 0)
    expect(result[Date.new(2026, 5, 1)]).to include(sale_refunds: 30, refunds: 30, sales: 0, cash_in: 0)
  end

  it 'reembolso de anticipo no concluido sólo cuenta como flujo' do
    order = make_order(status: 'Pending')
    pay(order, 40, Date.new(2026, 3, 10), status: 'Refunded', refunded_at: Date.new(2026, 4, 3))

    april = flows[Date.new(2026, 4, 1)]
    expect(april).to include(refunds: 40, sale_refunds: 0)
  end

  it 'compras: por fila usa total_order_cost cuando total_cost_mxn es 0, excluye canceladas' do
    purchase_order(order_date: Date.new(2026, 2, 3), total_cost_mxn: 500)
    purchase_order(order_date: Date.new(2026, 2, 20), total_cost_mxn: 0, total_order_cost: 300)
    purchase_order(order_date: Date.new(2026, 2, 21), total_cost_mxn: 999, status: 'Canceled')

    expect(flows[Date.new(2026, 2, 1)][:purchases]).to eq(800)
  end

  it 'altas manuales cuentan; piezas con purchase_order_id no' do
    po = purchase_order(order_date: Date.new(2025, 6, 1), total_cost_mxn: 70)
    manual = create(:inventory, product: product, purchase_cost: 150)
    manual.update_columns(created_at: Time.zone.local(2026, 7, 4, 12))
    linked = create(:inventory, product: product, purchase_cost: 70, purchase_order_id: po.id)
    linked.update_columns(created_at: Time.zone.local(2026, 7, 5, 12), purchase_order_item_id: nil)
    free = create(:inventory, product: product, purchase_cost: 0)
    free.update_columns(created_at: Time.zone.local(2026, 7, 6, 12))

    expect(flows[Date.new(2026, 7, 1)][:purchases]).to eq(150)
  end

  it 'agrupa la alta manual por la fecha local de created_at' do
    Time.use_zone('America/Mexico_City') do
      manual = create(:inventory, product: product, purchase_cost: 150)
      manual.update_columns(created_at: Time.zone.local(2026, 7, 31, 23)) # 1 ago en UTC
      result = flows
      expect(result[Date.new(2026, 7, 1)][:purchases]).to eq(150)
      expect(result[Date.new(2026, 8, 1)]).to be_nil
    end
  end

  it 'ignora datos fuera del rango y omite periodos sin datos' do
    order = make_order
    pay(order, 40, Date.new(2025, 12, 31))

    expect(flows).to eq({})
  end

  it 'agrupa por año con grain: :year' do
    order = make_order
    line(order, price: 100, cost: 60)
    pay(order, 40, Date.new(2026, 3, 10))
    pay(order, 60, Date.new(2026, 6, 2))
    purchase_order(order_date: Date.new(2026, 2, 3), total_cost_mxn: 500)

    result = flows(grain: :year)
    expect(result.keys).to eq([Date.new(2026, 1, 1)])
    expect(result[Date.new(2026, 1, 1)]).to include(sales: 100, cogs: 60, cash_in: 100, purchases: 500, sales_count: 1)
  end

  it 'rechaza un grain desconocido' do
    expect { described_class.new(range: range, grain: :week) }.to raise_error(ArgumentError)
  end
end
