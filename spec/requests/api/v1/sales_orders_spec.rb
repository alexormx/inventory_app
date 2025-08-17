require 'rails_helper'

RSpec.describe "Api::V1::SalesOrders", type: :request do
  before do
    # Bypass token auth for request specs
    allow_any_instance_of(Api::V1::SalesOrdersController).to receive(:authenticate_with_token!).and_return(true)
  end

  describe 'POST /api/v1/sales_orders - batch sample rows' do
    it 'processes 5 valid rows and some invalid ones' do
      rows_ok = [
        { id: 'SO-201601-001', order_date: '01/01/2015', subtotal: 0, discount: 0, tax_rate: 0, total_tax: 0, total_order_value: 50, carrier: 'Personal', tracking_number: 'A00000000MX', payment_method: 'cash', status: 'delivered', shipping_cost: 50, email: 'a21@hotmail.com' },
        { id: 'SO-201602-001', order_date: '10/02/2015', subtotal: 0, discount: 0, tax_rate: 0, total_tax: 0, total_order_value: 0, carrier: 'Personal', tracking_number: '', payment_method: 'cash', status: 'pending', shipping_cost: 0, email: 'a328@hotmail.com' },
        { id: 'SO-201602-002', order_date: '21/02/2015', subtotal: 0, discount: 0, tax_rate: 0, total_tax: 0, total_order_value: 0, carrier: 'Personal', tracking_number: '', payment_method: 'cash', status: 'canceled', shipping_cost: 0, email: 'a592@hotmail.com' },
        { id: 'SO-201602-003', order_date: '25/02/2015', subtotal: 0, discount: 0, tax_rate: 0, total_tax: 0, total_order_value: 50, carrier: 'Personal', tracking_number: '', payment_method: 'cash', status: 'confirmed', shipping_cost: 50, email: 'a141@hotmail.com' },
        { id: 'SO-201603-001', order_date: '01/03/2015', subtotal: 0, discount: 0, tax_rate: 0, total_tax: 0, total_order_value: 50, carrier: 'MercadoEnvio', tracking_number: 'A00000000MX', payment_method: 'bank_transfer', status: 'delivered', shipping_cost: 50, email: 'a248@hotmail.com' }
      ]

      # Append some invalid rows
      rows_nok = [
        # Unknown user (should 422)
        { id: 'SO-BAD-001', order_date: '01/01/2015', subtotal: 0, status: 'pending', email: 'noone@example.com', shipping_cost: 0 },
        # Negative subtotal (should 422 due to validation)
        { id: 'SO-BAD-002', order_date: '02/02/2015', subtotal: -1, status: 'delivered', payment_method: 'cash', email: 'a21@hotmail.com', shipping_cost: 0 }
      ]

      all_rows = rows_ok + rows_nok

      # Ensure users exist in the test DB for all rows
  # Only create users for known emails in OK rows and valid-NOK rows, skip the explicit unknown email
  emails_to_create = (rows_ok + rows_nok.reject { |r| r[:email] == 'noone@example.com' }).map { |r| r[:email] }.uniq
      emails_to_create.each do |email|
        User.create!(email: email, password: 'password', role: 'customer', created_offline: true) unless User.find_by(email: email)
      end

      pm_map = { 'cash' => 'efectivo', 'bank_transfer' => 'transferencia_bancaria' }

      all_rows.each do |r|
    payload = {
          sales_order: {
            order_date: r[:order_date],
            subtotal: r[:subtotal],
            tax_rate: r[:tax_rate] || 0,
            discount: r[:discount] || 0,
            status: r[:status],
            email: r[:email],
            carrier: r[:carrier],
            tracking_number: r[:tracking_number],
      payment_method: pm_map[r[:payment_method]] || r[:payment_method],
      shipping_cost: r.key?(:shipping_cost) ? r[:shipping_cost] : 0
          }
        }

        post '/api/v1/sales_orders', params: payload

        if rows_ok.map { |x| x[:id] }.include?(r[:id])
          expect(response).to have_http_status(:created), "expected created for #{r[:id]} but got #{response.status} - #{response.body}"
          body = JSON.parse(response.body)
          so = SaleOrder.find_by(id: body['sales_order']['id'])
          expect(so).not_to be_nil
          if %w[confirmed delivered].include?(r[:status].downcase)
            expect(so.payments.any?).to be true
          end
          if r[:status].downcase == 'delivered'
            expect(so.shipment).not_to be_nil
          end
        else
          # invalid rows should not create order
          expect(response.status).to eq(422)
        end
      end
    end
  end
end
