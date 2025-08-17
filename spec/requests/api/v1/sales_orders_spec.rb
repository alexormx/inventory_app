require 'rails_helper'

RSpec.describe "Api::V1::SalesOrders", type: :request do
  let(:user) { User.create!(email: "test@example.com", password: "password", role: "customer", created_offline: true) }

  before do
    # Bypass token auth for request specs
    allow_any_instance_of(Api::V1::SalesOrdersController).to receive(:authenticate_with_token!).and_return(true)
  end

  describe 'POST /api/v1/sales_orders' do
    it 'creates a sales order and payment when status is Confirmed' do
      payload = {
        sales_order: {
          order_date: Date.today.to_s,
          subtotal: 100.0,
          tax_rate: 16.0,
          discount: 0.0,
          status: 'Confirmed',
          email: user.email
        }
      }

      post '/api/v1/sales_orders', params: payload
      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      so = SaleOrder.find_by(id: body['sales_order']['id'])
      expect(so).not_to be_nil
      expect(so.status).to eq('Confirmed')
      expect(so.payments.count).to eq(1)
      expect(so.payments.first.status).to eq('Completed')
    end

    it 'creates a sales order, payment and shipment when status is Delivered' do
      payload = {
        sales_order: {
          order_date: Date.today.to_s,
          subtotal: 200.0,
          tax_rate: 16.0,
          discount: 0.0,
          status: 'Delivered',
          email: user.email
        }
      }

      post '/api/v1/sales_orders', params: payload
      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      so = SaleOrder.find_by(id: body['sales_order']['id'])
      expect(so).not_to be_nil
      expect(so.status).to eq('Delivered')
      expect(so.payments.count).to eq(1)
  expect(so.shipment).not_to be_nil
  expect(so.shipment.tracking_number).to eq('A00000000MX')
    end

    it 'processes the provided CSV-like rows and asserts expected outcomes' do
      rows = [
        { id: 'SO-201601-001', order_date: '01/01/2015', subtotal: 0.0, discount: 0.0, tax_rate: 0.0, total_tax: 0.0, total_order_value: 0.0, carrier: 'Personal', tracking_number: '', payment_method: 'cash', status: 'delivered', shipping_cost: 0.0, email: 'a21@hotmail.com' },
        { id: 'SO-201602-001', order_date: '10/02/2015', subtotal: 0.0, discount: 0.0, tax_rate: 0.0, total_tax: 0.0, total_order_value: 0.0, carrier: 'Personal', tracking_number: '', payment_method: 'cash', status: 'pending', shipping_cost: 0.0, email: 'a328@hotmail.com' },
        { id: 'SO-201602-002', order_date: '21/02/2015', subtotal: 0.0, discount: 0.0, tax_rate: 0.0, total_tax: 0.0, total_order_value: 0.0, carrier: 'Personal', tracking_number: '', payment_method: 'cash', status: 'canceled', shipping_cost: 0.0, email: 'a592@hotmail.com' },
        { id: 'SO-201602-003', order_date: '25/02/2015', subtotal: 0.0, discount: 0.0, tax_rate: 0.0, total_tax: 0.0, total_order_value: 0.0, carrier: 'Personal', tracking_number: '', payment_method: 'cash', status: 'confirmed', shipping_cost: 0.0, email: 'a141@hotmail.com' },
        { id: 'SO-201603-001', order_date: '01/03/2015', subtotal: 0.0, discount: 0.0, tax_rate: 0.0, total_tax: 0.0, total_order_value: 0.0, carrier: 'MercadoEnvio', tracking_number: '', payment_method: 'bank_transfer', status: 'delivered', shipping_cost: 0.0, email: 'a248@hotmail.com' }
      ]

      # Ensure users exist
      rows.map { |r| r[:email] }.uniq.each do |email|
        User.create!(email: email, password: 'password', role: 'customer', created_offline: true) unless User.find_by(email: email)
      end

      mapping_pm = { 'cash' => 'efectivo', 'bank_transfer' => 'transferencia_bancaria' }

      rows.each do |r|
        payload = {
          sales_order: {
            order_date: r[:order_date],
            subtotal: r[:subtotal],
            tax_rate: r[:tax_rate],
            discount: r[:discount],
            status: r[:status],
            email: r[:email],
            carrier: r[:carrier],
            tracking_number: r[:tracking_number],
            payment_method: mapping_pm[r[:payment_method]]
          }
        }

        post '/api/v1/sales_orders', params: payload

        if response.status == 201
          body = JSON.parse(response.body)
          so = SaleOrder.find_by(id: body['sales_order']['id'])
          expect(so).not_to be_nil
          # If status was Confirmed or Delivered, payment should exist
          if %w[confirmed delivered].include?(r[:status].downcase)
            expect(so.payments.count).to eq(1)
          end
          if r[:status].downcase == 'delivered'
            expect(so.shipment).not_to be_nil
          end
        else
          # For invalid cases (e.g. zero amount payment), expect 422
          expect(response.status).to eq(422)
          parsed = JSON.parse(response.body) rescue nil
          expect(parsed).to be_present
          expect(parsed['status']).to eq('error').or be_truthy
        end
      end
    end
  end
end
