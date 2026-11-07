require 'rails_helper'

RSpec.describe Finance::ClosingBalances do
  let(:product) { create(:product, skip_seed_inventory: true) }

  def balances(*dates)
    described_class.new(dates: dates).call
  end

  def make_order(total: 100, status: 'Pending')
    order = create(:sale_order)
    order.update_columns(total_order_value: total, status: status, order_date: Date.new(2026, 1, 5))
    order
  end

  def pay(order, amount, paid_at, status: 'Completed', refunded_at: nil)
    payment = create(:payment, sale_order: order, amount: amount)
    payment.update_columns(paid_at: paid_at, status: status, refunded_at: refunded_at)
    payment
  end

  def piece(cost:, created_at: Time.zone.local(2026, 1, 15, 12), **attrs)
    inv = create(:inventory, product: product, purchase_cost: cost)
    inv.update_columns(created_at: created_at, **attrs)
    inv
  end

  def status_int(name)
    Inventory.statuses.fetch(name)
  end

  it 'anticipo por entregar hasta que la venta concluye' do
    order = make_order
    pay(order, 40, Date.new(2026, 3, 10))
    pay(order, 60, Date.new(2026, 6, 2))
    order.update_columns(status: 'Delivered')

    result = balances(Date.new(2026, 2, 28), Date.new(2026, 3, 31), Date.new(2026, 5, 31), Date.new(2026, 6, 30))
    expect(result[Date.new(2026, 2, 28)][:advances]).to eq(0)
    expect(result[Date.new(2026, 3, 31)][:advances]).to eq(40)
    expect(result[Date.new(2026, 5, 31)][:advances]).to eq(40)
    expect(result[Date.new(2026, 6, 30)][:advances]).to eq(0)
    expect(result[Date.new(2026, 3, 31)][:advances]).to be_a(BigDecimal)
  end

  it 'anticipo reembolsado deja de contar desde su refunded_at' do
    order = make_order
    pay(order, 40, Date.new(2026, 3, 10), status: 'Refunded', refunded_at: Date.new(2026, 4, 15))

    result = balances(Date.new(2026, 3, 31), Date.new(2026, 4, 14), Date.new(2026, 4, 30))
    expect(result[Date.new(2026, 3, 31)][:advances]).to eq(40)
    expect(result[Date.new(2026, 4, 14)][:advances]).to eq(40)
    expect(result[Date.new(2026, 4, 30)][:advances]).to eq(0)
  end

  it 'orden cancelada con pago no reembolsado sigue como anticipo; devuelta no' do
    canceled = make_order(status: 'Canceled')
    pay(canceled, 100, Date.new(2026, 3, 10))
    returned = make_order(status: 'Returned')
    pay(returned, 50, Date.new(2026, 3, 10))

    expect(balances(Date.new(2026, 3, 31))[Date.new(2026, 3, 31)][:advances]).to eq(100)
  end

  it 'inventario: entra por order_date de la PO y sale al concluir su venta' do
    po = create(:purchase_order)
    po.update_columns(order_date: Date.new(2026, 2, 1), status: 'Delivered')
    inv = create(:inventory, product: product, purchase_cost: 80, purchase_order_id: po.id)
    inv.update_columns(created_at: Time.zone.local(2026, 2, 20, 12))
    order = make_order
    pay(order, 100, Date.new(2026, 4, 10))
    order.update_columns(status: 'Delivered')
    inv.update_columns(sale_order_id: order.id, status: status_int('sold'),
                       status_changed_at: Time.zone.local(2026, 3, 1, 12))

    result = balances(Date.new(2026, 1, 31), Date.new(2026, 2, 28), Date.new(2026, 3, 31), Date.new(2026, 4, 30))
    expect(result.transform_values { |b| b[:inventory] }).to eq(
      Date.new(2026, 1, 31) => 0, Date.new(2026, 2, 28) => 80, Date.new(2026, 3, 31) => 80, Date.new(2026, 4, 30) => 0
    )
  end

  it 'inventario: pieza de orden no concluida o de PO cancelada' do
    order = make_order # sin pagos, Pending: no concluida
    piece(cost: 25, sale_order_id: order.id, status: status_int('reserved'))
    canceled_po = create(:purchase_order)
    canceled_po.update_columns(order_date: Date.new(2026, 1, 2), status: 'Canceled')
    piece(cost: 999, purchase_order_id: canceled_po.id)

    expect(balances(Date.new(2026, 1, 31))[Date.new(2026, 1, 31)][:inventory]).to eq(25)
  end

  it 'inventario: pieza dañada sale en status_changed_at; sold sin orden también' do
    piece(cost: 10, status: status_int('damaged'), status_changed_at: Time.zone.local(2026, 3, 5, 12))
    piece(cost: 20, status: status_int('sold'), status_changed_at: Time.zone.local(2026, 4, 5, 12))
    piece(cost: 40, status: status_int('returned'), status_changed_at: Time.zone.local(2026, 3, 5, 12))

    result = balances(Date.new(2026, 2, 28), Date.new(2026, 3, 31), Date.new(2026, 4, 30))
    expect(result.transform_values { |b| b[:inventory] }).to eq(
      Date.new(2026, 2, 28) => 70, Date.new(2026, 3, 31) => 60, Date.new(2026, 4, 30) => 40
    )
  end

  it 'inventario: fechas de created_at y status_changed_at en la zona de la app' do
    Time.use_zone('America/Mexico_City') do
      piece(cost: 10, created_at: Time.zone.local(2026, 1, 31, 23)) # 1 feb en UTC
      piece(cost: 20, created_at: Time.zone.local(2026, 1, 10, 12), status: status_int('lost'),
                      status_changed_at: Time.zone.local(2026, 1, 31, 23))
      expect(balances(Date.new(2026, 1, 31))[Date.new(2026, 1, 31)][:inventory]).to eq(10)
    end
  end

  it 'devuelve una entrada por cada fecha aunque no haya datos' do
    d1 = Date.new(2026, 1, 31)
    d2 = Date.new(2026, 2, 28)
    expect(balances(d1, d2)).to eq(d1 => { advances: 0, inventory: 0 }, d2 => { advances: 0, inventory: 0 })
  end

  it 'sin fechas devuelve un hash vacío' do
    expect(balances).to eq({})
  end

  describe '.inventory_movements_sql' do
    it 'devuelve purchase_cost, entered_on y exited_on' do
      piece(cost: 10, status: status_int('scrap'), status_changed_at: Time.zone.local(2026, 3, 5, 12))
      row = ActiveRecord::Base.connection.select_all(described_class.inventory_movements_sql).to_a.first
      expect(row.keys).to contain_exactly('purchase_cost', 'entered_on', 'exited_on')
      expect(row['entered_on'].to_s).to eq('2026-01-15')
      expect(row['exited_on'].to_s).to eq('2026-03-05')
    end
  end
end
