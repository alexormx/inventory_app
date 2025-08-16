require 'rails_helper'

RSpec.describe "Api::V1::PurchaseOrders", type: :request do
	let(:admin) { User.create!(email: 'admin@example.com', password: 'password', role: 'admin', api_token: SecureRandom.hex(16)) }
	let(:supplier) { User.create!(email: 'supplier@example.com', password: 'password', role: 'supplier') }

	let(:headers) { { 'Authorization' => "Token #{admin.api_token}" } }

	describe 'POST /api/v1/purchase_orders' do
		it 'creates a purchase order when user exists and auth is valid' do
			post '/api/v1/purchase_orders', params: {
				purchase_order: {
					id: 'PO-201501-001',
					order_date: '2015-01-01',
					currency: 'MXN',
					exchange_rate: '1.0',
					tax_cost: '12.0',
					shipping_cost: '5.0',
					other_cost: '0.0',
					subtotal: '100.0',
					total_order_cost: '117.0',
					status: 'Delivered',
					email: supplier.email,
					expected_delivery_date: '2015-01-06',
					actual_delivery_date: '2015-01-06'
				}
			}, headers: headers

			expect(response).to have_http_status(:created)
			json = JSON.parse(response.body)
			expect(json['status']).to eq('success')
			expect(json['purchase_order']['id']).to eq('PO-201501-001')
		end

		it 'returns error when user not found' do
			post '/api/v1/purchase_orders', params: {
				purchase_order: {
					id: 'PO-201501-002',
					order_date: '2015-01-01',
					currency: 'MXN',
					exchange_rate: '1.0',
					tax_cost: '0.0',
					shipping_cost: '0.0',
					other_cost: '0.0',
					subtotal: '0.0',
					total_order_cost: '0.0',
					status: 'Pending',
					email: 'missing@example.com',
					expected_delivery_date: '2015-01-06'
				}
			}, headers: headers

			expect(response).to have_http_status(:unprocessable_entity)
			json = JSON.parse(response.body)
			expect(json['status']).to eq('error')
			expect(json['message']).to match(/User not found/)
		end
	end
end

