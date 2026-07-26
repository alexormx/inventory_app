# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::SaleOrders#cancel', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }
  let(:order) { create(:sale_order, user: customer, status: 'Pending') }

  before { sign_in admin }

  it 'cancels an unpaid pending order with a truthful notice' do
    post cancel_admin_sale_order_path(order)

    expect(response).to redirect_to(admin_sale_order_path(order))
    expect(flash[:notice]).to include('inventario reservado', 'no se modificaron pagos')
    expect(order.reload.status).to eq('Canceled')
  end

  it 'shows a safe payment/refund-review message for a partially paid order' do
    payment = create(:payment, sale_order: order, amount: 40, status: 'Completed')

    post cancel_admin_sale_order_path(order)

    expect(response).to redirect_to(admin_sale_order_path(order))
    expect(flash[:alert]).to match(/revisión de pago y reembolso/)
    expect(order.reload.status).to eq('Pending')
    expect(payment.reload.status).to eq('Completed')
  end

  it 'does not expose an unexpected internal exception' do
    service = instance_double(SaleOrders::CancelOrderService)
    allow(SaleOrders::CancelOrderService).to receive(:new).with(order).and_return(service)
    allow(service).to receive(:call).and_raise(StandardError, 'sensitive internal details')

    post cancel_admin_sale_order_path(order)

    expect(flash[:alert]).to include('solicita una revisión administrativa')
    expect(flash[:alert]).not_to include('sensitive internal details')
  end
end
