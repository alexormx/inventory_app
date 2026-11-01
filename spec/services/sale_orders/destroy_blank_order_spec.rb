# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SaleOrders::DestroyBlankOrder do
  let(:order) { create(:sale_order, total_order_value: 0, subtotal: 0) }

  it 'deletes a blank pending order with its shipping snapshot and unpaid payments' do
    create(:order_shipping_address, sale_order: order)
    create(:payment, sale_order: order, amount: 50, status: 'Pending')

    result = described_class.call(order)

    expect(result).to be_success
    expect(SaleOrder.exists?(order.id)).to be(false)
    expect(Payment.where(sale_order_id: order.id)).to be_empty
    expect(OrderShippingAddress.where(sale_order_id: order.id)).to be_empty
  end

  it 'deletes a blank canceled order' do
    order.update_columns(status: 'Canceled')

    expect(described_class.call(order)).to be_success
  end

  it 'keeps orders that have products' do
    create(:sale_order_item, sale_order: order)

    result = described_class.call(order)

    expect(result).not_to be_success
    expect(result.reasons).to include('tiene productos')
    expect(SaleOrder.exists?(order.id)).to be(true)
  end

  it 'keeps orders with received payments, a shipment or inventory' do
    create(:payment, sale_order: order, amount: 10, status: 'Completed')
    create(:shipment, sale_order: order)
    create(:inventory, sale_order: order, status: :reserved)

    reasons = described_class.blocking_reasons(order.reload)

    expect(reasons).to include('tiene pagos recibidos o reembolsados', 'tiene un envío registrado',
                               'tiene piezas de inventario asignadas')
  end

  it 'deletes a blank $0 order that confirmed itself' do
    order.update_columns(status: 'Confirmed')

    expect(described_class.call(order)).to be_success
  end

  it 'keeps orders already in preparation or shipped, even when blank' do
    order.update_columns(status: 'Preparing')

    expect(described_class.blocking_reasons(order)).to include('solo se pueden borrar pedidos pendientes, confirmados o cancelados')
  end
end
