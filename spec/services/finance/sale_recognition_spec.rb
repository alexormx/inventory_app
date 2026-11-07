require 'rails_helper'

RSpec.describe Finance::SaleRecognition do
  def make_order(user: nil)
    create(:sale_order, **(user ? { user: user } : {}))
  end

  def pay(order, amount, paid_at, status: 'Completed')
    payment = create(:payment, sale_order: order, amount: amount, status: status)
    payment.update_columns(paid_at: paid_at, status: status)
    payment
  end

  def finalize(order, status:, order_date: nil)
    attrs = { total_order_value: 100, status: status }
    attrs[:order_date] = order_date if order_date
    order.update_columns(attrs)
  end

  def concluded(order)
    described_class.concluded_on_by_order[order.id]
  end

  it 'anticipo en marzo y liquidación en junio → concluye en junio' do
    order = make_order
    pay(order, 40, Date.new(2026, 3, 10))
    pay(order, 60, Date.new(2026, 6, 2))
    finalize(order, status: 'Delivered')
    expect(concluded(order)).to eq(Date.new(2026, 6, 2))
  end

  it 'no concluye mientras falta pagar' do
    order = make_order
    pay(order, 40, Date.new(2026, 3, 10))
    finalize(order, status: 'Pending')
    expect(concluded(order)).to be_nil
  end

  it 'pago extra posterior no mueve la conclusión' do
    order = make_order
    pay(order, 100, Date.new(2026, 3, 1))
    pay(order, 20, Date.new(2026, 5, 1))
    finalize(order, status: 'Delivered')
    expect(concluded(order)).to eq(Date.new(2026, 3, 1))
  end

  it 'un reembolso posterior no la des-concluye' do
    order = make_order
    pay(order, 100, Date.new(2026, 3, 1), status: 'Refunded')
    finalize(order, status: 'Pending')
    expect(concluded(order)).to eq(Date.new(2026, 3, 1))
  end

  it 'ignora pagos sin paid_at' do
    order = make_order
    pay(order, 100, nil)
    finalize(order, status: 'Pending')
    expect(concluded(order)).to be_nil
  end

  it 'excluye canceladas y devueltas' do
    %w[Canceled Returned].each do |status|
      order = make_order
      pay(order, 100, Date.new(2026, 3, 1))
      finalize(order, status: status)
      expect(concluded(order)).to be_nil
    end
  end

  it 'orden antigua sin pagos cuenta en su order_date' do
    order = make_order
    finalize(order, status: 'Delivered', order_date: Date.new(2024, 5, 1))
    expect(concluded(order)).to eq(Date.new(2024, 5, 1))
  end

  it 'orden a crédito sin liquidar no se reconoce' do
    user = create(:user)
    user.update_columns(credit_enabled: true)
    order = make_order(user: user)
    finalize(order, status: 'Delivered', order_date: Date.new(2024, 5, 1))
    expect(concluded(order)).to be_nil
  end

  it 'orden con pago parcial no usa el respaldo' do
    order = make_order
    pay(order, 40, Date.new(2026, 3, 10))
    finalize(order, status: 'Delivered', order_date: Date.new(2024, 5, 1))
    expect(concluded(order)).to be_nil
  end
end
