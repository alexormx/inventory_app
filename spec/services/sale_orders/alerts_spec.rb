# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SaleOrders::Alerts do
  def order(status: 'Pending', age: 40.days, total: 100)
    # Se crea normal y luego se fija el estado: "Canceled" sólo se alcanza por
    # SaleOrders::CancelOrderService, así que no se pasa al crear.
    create(:sale_order).tap do |o|
      o.update_columns(status: status, created_at: age.ago, total_order_value: total)
    end
  end

  def pay(order, amount, status: 'Completed')
    Payment.insert_all!([{ sale_order_id: order.id, amount: amount, status: status, payment_method: 2,
                           created_at: Time.current, updated_at: Time.current }])
  end

  def unit(order, status)
    create(:inventory, product: create(:product, skip_seed_inventory: true), status: :damaged)
      .tap { |i| i.update_columns(status: Inventory.statuses[status], sale_order_id: order.id) }
  end

  it 'lista órdenes Pending de más de 30 días con lo abonado y las unidades retenidas' do
    old = order
    pay(old, 30)
    unit(old, 'reserved')
    unit(old, 'reserved')
    order(age: 10.days)

    rows = described_class.stale_pending.to_a
    expect(rows.map(&:id)).to eq([old.id])
    expect(rows.first.paid_amount.to_d).to eq(30)
    expect(rows.first.held_units).to eq(2)
  end

  it 'lista órdenes no canceladas con pagos completados mayores al total' do
    over = order(status: 'Delivered', total: 100)
    pay(over, 150)
    pending_payment = order(status: 'Delivered', total: 100)
    pay(pending_payment, 150, status: 'Pending')
    exact = order(status: 'Delivered', total: 100)
    pay(exact, 100.005)
    canceled = order(status: 'Canceled', total: 100)
    pay(canceled, 150)

    expect(described_class.overpaid.map(&:id)).to eq([over.id])
  end

  it 'lista órdenes Pending con unidades ya vendidas' do
    bad = order(age: 1.day)
    unit(bad, 'sold')
    fine = order(age: 1.day)
    unit(fine, 'reserved')

    expect(described_class.inconsistent.map(&:id)).to eq([bad.id])
  end

  it 'cuenta las tres alertas' do
    order
    expect(described_class.counts).to eq(stale_pending: 1, overpaid: 0, inconsistent: 0)
  end
end
