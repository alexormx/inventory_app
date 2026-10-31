# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MercadoPago::CreatePreference do
  let(:user) { create(:user, name: 'Ana Cliente') }
  let(:order) { create(:sale_order, user: user, total_order_value: 412.5, subtotal: 412.5) }
  let(:client) { instance_double(MercadoPago::Client) }
  let(:urls) do
    { success: 'https://x.test/back', pending: 'https://x.test/back', failure: 'https://x.test/back',
      notification: 'https://x.test/webhooks/mercado_pago' }
  end

  it 'charges the pending payment amount as one line in MXN and returns the Mercado Pago URL' do
    payment = create(:payment, sale_order: order, amount: 412.5, payment_method: 'mercado_pago', status: 'Pending')
    sent = nil
    allow(client).to receive(:create_preference) do |body, **|
      sent = body
      { 'id' => 'pref-1', 'init_point' => 'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref-1' }
    end

    result = described_class.call(sale_order: order, urls: urls, client: client)

    expect(result.redirect_url).to include('pref_id=pref-1')
    expect(payment.reload.provider_preference_id).to eq('pref-1')
    expect(sent[:external_reference]).to eq(order.id.to_s)
    expect(sent[:items]).to eq([{ id: order.id.to_s, title: "Pedido #{order.id} - Pasatiempos a Escala",
                                  quantity: 1, currency_id: 'MXN', unit_price: 412.5 }])
    expect(sent[:notification_url]).to eq(urls[:notification])
  end

  it 'refuses orders without a pending Mercado Pago payment or that were canceled' do
    expect(described_class.call(sale_order: order, urls: urls, client: client)).not_to be_success

    create(:payment, sale_order: order, amount: 412.5, payment_method: 'mercado_pago', status: 'Pending')
    order.update_columns(status: 'Canceled')
    expect(described_class.call(sale_order: order, urls: urls, client: client)).not_to be_success
  end

  it 'returns a friendly error when Mercado Pago fails' do
    create(:payment, sale_order: order, amount: 412.5, payment_method: 'mercado_pago', status: 'Pending')
    allow(client).to receive(:create_preference).and_raise(MercadoPago::Error, 'Mercado Pago respondió 500')

    result = described_class.call(sale_order: order, urls: urls, client: client)

    expect(result.error).to include('No pudimos abrir Mercado Pago')
  end
end
