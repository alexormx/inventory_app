# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MercadoPago::SyncPayment do
  let(:order) { create(:sale_order, total_order_value: 350, subtotal: 350) }
  let!(:payment) { create(:payment, sale_order: order, amount: 350, payment_method: 'mercado_pago', status: 'Pending') }
  let(:client) { instance_double(MercadoPago::Client) }

  def api_payment(id, status:, amount: 350, currency: 'MXN', ref: order.id.to_s)
    allow(client).to receive(:payment).with(id).and_return(
      'id' => id.to_i, 'status' => status, 'status_detail' => "detail_#{status}", 'payment_type_id' => 'credit_card',
      'transaction_amount' => amount, 'currency_id' => currency, 'external_reference' => ref
    )
  end

  def sync(id) = described_class.call(provider_payment_id: id, client: client)

  it 'completes the payment and confirms the order when Mercado Pago approves it' do
    api_payment('111', status: 'approved')

    result = sync('111')

    expect(result.provider_status).to eq('approved')
    expect(payment.reload).to have_attributes(status: 'Completed', provider_payment_id: '111', provider_payment_type: 'credit_card')
    expect(order.reload.status).to eq('Confirmed')
  end

  it 'is idempotent when the same notification arrives twice' do
    api_payment('111', status: 'approved')

    2.times { sync('111') }

    expect(payment.reload.status).to eq('Completed')
    expect(order.payments.count).to eq(1)
  end

  it 'keeps the payment pending for OXXO/SPEI and for rejected attempts so the customer can retry' do
    api_payment('222', status: 'pending')
    sync('222')
    expect(payment.reload).to have_attributes(status: 'Pending', provider_status: 'pending')

    api_payment('333', status: 'rejected')
    sync('333')
    expect(payment.reload).to have_attributes(status: 'Pending', provider_status: 'rejected')
  end

  it 'does not let a later rejected attempt undo an approved one' do
    api_payment('111', status: 'approved')
    api_payment('444', status: 'rejected')

    sync('111')
    sync('444')

    expect(payment.reload).to have_attributes(status: 'Completed', provider_payment_id: '111')
  end

  it 'does not complete the payment when the charged amount or currency does not match' do
    api_payment('555', status: 'approved', amount: 10)
    sync('555')
    expect(payment.reload).to have_attributes(status: 'Pending', provider_status: 'amount_mismatch')

    api_payment('556', status: 'approved', currency: 'USD')
    sync('556')
    expect(payment.reload.status).to eq('Pending')
  end

  it 'marks a completed payment as refunded' do
    api_payment('111', status: 'approved')
    sync('111')
    api_payment('111', status: 'refunded')
    sync('111')

    expect(payment.reload.status).to eq('Refunded')
    expect(order.reload.status).to eq('Pending')
  end

  it 'ignores payments for unknown orders' do
    api_payment('777', status: 'approved', ref: 'SO-NOEXISTE')

    expect(sync('777').ignored_reason).to be_present
    expect(payment.reload.status).to eq('Pending')
  end
end
