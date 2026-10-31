# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Mercado Pago Checkout Pro', type: :request do
  let(:user) { create(:user) }

  describe 'checkout' do
    let(:product) { create(:product, selling_price: 100.00) }
    let(:address) { create(:shipping_address, user: user, default: true) }
    let!(:shipping_method) { create(:shipping_method, :standard) }
    let!(:mp_method) { create(:payment_method, name: 'Mercado Pago', code: 'mercado_pago', account_number: nil, instructions: nil) }

    before do
      sign_in user
      post cart_items_path, params: { product_id: product.id, quantity: 1 }
      post checkout_step2_path, params: { selected_address_id: address.id, shipping_method: shipping_method.code }
    end

    it 'does not offer Mercado Pago while it has no credentials' do
      get checkout_step3_path

      expect(response.body).not_to include('value="mercado_pago"')
    end

    it 'creates the order and sends the customer to Mercado Pago' do
      allow(MercadoPago).to receive(:configured?).and_return(true)
      allow(MercadoPago::CreatePreference).to receive(:call)
        .and_return(MercadoPago::CreatePreference::Result.new(redirect_url: 'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=p1'))

      get checkout_step3_path
      expect(response.body).to include('value="mercado_pago"')

      post checkout_complete_path, params: { payment_method: 'mercado_pago', checkout_token: session[:checkout_token], accept_pending: '1' }

      order = user.sale_orders.last
      expect(order.payments.last).to have_attributes(payment_method: 'mercado_pago', status: 'Pending')
      expect(response).to redirect_to('https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=p1')
      expect(MercadoPago::CreatePreference).to have_received(:call)
        .with(sale_order: order, urls: hash_including(notification: 'http://www.example.com/webhooks/mercado_pago'))
    end
  end

  describe 'returning from Mercado Pago' do
    let(:order) { create(:sale_order, user: user) }

    before do
      create(:payment, sale_order: order, amount: 100, payment_method: 'mercado_pago', status: 'Pending')
      sign_in user
    end

    it 'confirms against the API, not the status in the URL' do
      allow(MercadoPago::SyncPayment).to receive(:call).with(provider_payment_id: '999')
                                                        .and_return(MercadoPago::SyncPayment::Result.new(provider_status: 'rejected'))

      get mercado_pago_return_path, params: { payment_id: '999', status: 'approved', external_reference: order.id }

      expect(response).to redirect_to(checkout_thank_you_path(order_id: order.id))
      expect(flash[:alert]).to include('no se completó')
    end

    it "does not reveal another customer's order" do
      other = create(:sale_order)

      get mercado_pago_return_path, params: { payment_id: '999', external_reference: other.id }

      expect(response).to redirect_to(orders_path)
    end

    it 'offers to retry from the order page after a rejected attempt' do
      order.payments.last.update!(provider_status: 'rejected')
      allow(MercadoPago).to receive(:configured?).and_return(true)

      get checkout_thank_you_path(order_id: order.id)

      expect(response.body).to include('Pagar con Mercado Pago', 'no se completó')
    end
  end

  describe 'webhook' do
    let(:secret) { 'whsec' }

    def signed_headers(data_id, request_id: 'req-1', ts: '1704908010')
      manifest = "id:#{data_id};request-id:#{request_id};ts:#{ts};"
      { 'x-signature' => "ts=#{ts},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, manifest)}", 'x-request-id' => request_id }
    end

    before { allow(MercadoPago).to receive(:webhook_secret).and_return(secret) }

    it 'queues a sync for a correctly signed payment notification' do
      expect do
        post webhooks_mercado_pago_path(type: 'payment', 'data.id' => '123'),
             params: { type: 'payment', data: { id: '123' } }.to_json,
             headers: signed_headers('123').merge('CONTENT_TYPE' => 'application/json')
      end.to have_enqueued_job(MercadoPago::SyncPaymentJob).with('123')

      expect(response).to have_http_status(:ok)
    end

    it 'rejects an unsigned or forged notification without queuing anything' do
      expect do
        post webhooks_mercado_pago_path(type: 'payment', 'data.id' => '123'), headers: signed_headers('999')
      end.not_to have_enqueued_job(MercadoPago::SyncPaymentJob)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'acknowledges other topics so Mercado Pago does not retry them' do
      post webhooks_mercado_pago_path(topic: 'merchant_order', id: '5')

      expect(response).to have_http_status(:ok)
    end
  end
end
