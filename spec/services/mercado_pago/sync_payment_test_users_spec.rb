# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MercadoPago::SyncPayment, 'with test users and tickets' do
  let(:order) { create(:sale_order, total_order_value: 350, subtotal: 350, idempotency_key: SecureRandom.uuid) }
  let!(:payment) { create(:payment, sale_order: order, amount: 350, payment_method: 'mercado_pago', status: 'Pending') }
  let(:client) { instance_double(MercadoPago::Client) }

  def api_payment(id, status:, live_mode: true, ticket_url: nil, type: 'credit_card')
    allow(client).to receive(:payment).with(id).and_return(
      'id' => id.to_i, 'status' => status, 'status_detail' => 'x', 'payment_type_id' => type,
      'transaction_amount' => 350, 'currency_id' => 'MXN', 'external_reference' => order.id.to_s,
      'live_mode' => live_mode, 'transaction_details' => { 'external_resource_url' => ticket_url }
    )
  end

  def sync(id) = described_class.call(provider_payment_id: id, client: client)

  it 'treats every payment as a test while MERCADOPAGO_TEST_MODE is on, even with live_mode: true' do
    allow(MercadoPago).to receive(:test_mode?).and_return(true)
    api_payment('100', status: 'approved', live_mode: true)

    expect(sync('100')).to be_test_payment
    expect(payment.reload.status).to eq('Pending')
    expect(order.reload.status).to eq('Canceled')
  end

  it 'undoes a test charge that was recorded as real and cancels the order' do
    allow(MercadoPago).to receive(:test_mode?).and_return(false)
    api_payment('100', status: 'approved', live_mode: true)
    sync('100')
    expect(order.reload.status).to eq('Confirmed')

    allow(MercadoPago).to receive(:test_mode?).and_return(true)
    sync('100')

    expect(payment.reload).to have_attributes(status: 'Pending', paid_at: nil)
    expect(order.reload.status).to eq('Canceled')
  end

  it 'never touches a different charge that was already completed' do
    allow(MercadoPago).to receive(:test_mode?).and_return(false)
    api_payment('100', status: 'approved')
    sync('100')

    allow(MercadoPago).to receive(:test_mode?).and_return(true)
    api_payment('200', status: 'approved')
    sync('200')

    expect(payment.reload).to have_attributes(status: 'Completed', provider_payment_id: '100')
  end

  it 'stores the OXXO ticket and emails it once' do
    allow(MercadoPago).to receive(:test_mode?).and_return(false)
    api_payment('300', status: 'pending', type: 'ticket', ticket_url: 'https://www.mercadopago.com.mx/payments/300/ticket')

    expect { sync('300') }.to have_enqueued_mail(OrderConfirmationMailer, :mercado_pago_ticket).once
    expect(payment.reload.provider_ticket_url).to eq('https://www.mercadopago.com.mx/payments/300/ticket')

    expect { sync('300') }.not_to have_enqueued_mail(OrderConfirmationMailer, :mercado_pago_ticket)
  end

  it 'confirms the order when a pending OXXO payment is later approved (webhook)' do
    allow(MercadoPago).to receive(:test_mode?).and_return(false)
    api_payment('400', status: 'pending', type: 'ticket', ticket_url: 'https://mp/ticket/400')
    sync('400')
    expect(order.reload.status).to eq('Pending')

    api_payment('400', status: 'approved', type: 'ticket', ticket_url: 'https://mp/ticket/400')

    expect { sync('400') }.to have_enqueued_mail(OrderConfirmationMailer, :payment_confirmation)
    expect(payment.reload.status).to eq('Completed')
    expect(order.reload.status).to eq('Confirmed')
  end
end
