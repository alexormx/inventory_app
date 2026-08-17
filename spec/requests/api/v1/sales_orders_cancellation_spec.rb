# frozen_string_literal: true

require 'rails_helper'

# La API podía llevar una orden viva a 'Canceled' con un update! directo,
# saltándose las validaciones de pago, envío e inventario. Ahora enruta por
# SaleOrders::CancelOrderService. La importación histórica de órdenes que ya
# nacen canceladas debe seguir funcionando: es cómo se cargó el histórico.
RSpec.describe 'Api::V1::SalesOrders cancellation', type: :request do
  before do
    allow_any_instance_of(Api::V1::SalesOrdersController)
      .to receive(:authenticate_with_token!).and_return(true)
  end

  let(:customer) { create(:user, email: 'api-cancel@example.com') }
  let(:product) { create(:product, selling_price: 100.0, minimum_price: 10.0) }

  describe 'creating a historical record that is already canceled' do
    it 'imports it as Canceled' do
      post '/api/v1/sales_orders', params: {
        sales_order: {
          order_date: '01/02/2015', subtotal: 0, tax_rate: 0, discount: 0,
          status: 'canceled', email: customer.email, shipping_cost: 0
        }
      }

      expect(response).to have_http_status(:created), response.body
      order = SaleOrder.find(JSON.parse(response.body)['sales_order']['id'])
      expect(order.status).to eq('Canceled')
    end

    it 'accepts the double-l spelling used by the legacy exporter' do
      post '/api/v1/sales_orders', params: {
        sales_order: {
          order_date: '03/02/2015', subtotal: 0, tax_rate: 0, discount: 0,
          status: 'cancelled', email: customer.email, shipping_cost: 0
        }
      }

      expect(response).to have_http_status(:created), response.body
      order = SaleOrder.find(JSON.parse(response.body)['sales_order']['id'])
      expect(order.status).to eq('Canceled')
    end
  end

  describe 'cancelling an existing live order' do
    let(:order) do
      create(:sale_order, user: customer, status: 'Pending',
                          subtotal: 100.0, total_order_value: 100.0)
    end

    it 'releases reserved inventory through the canonical service' do
      inventory = create(:inventory, product: product, status: :reserved,
                                     sale_order_id: order.id, sold_price: 100.0)

      patch "/api/v1/sales_orders/#{order.id}", params: { sales_order: { status: 'canceled' } }

      expect(response).to have_http_status(:ok), response.body
      expect(order.reload.status).to eq('Canceled')
      inventory.reload
      expect(inventory.status).to eq('available')
      expect(inventory.sale_order_id).to be_nil
      expect(inventory.sold_price).to be_nil
    end

    it 'is rejected when the order holds sold inventory, leaving it linked' do
      inventory = create(:inventory, product: product, status: :sold,
                                     sale_order_id: order.id, sold_price: 100.0)
      order.update_column(:status, 'Confirmed')

      patch "/api/v1/sales_orders/#{order.id}", params: { sales_order: { status: 'canceled' } }

      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(order.reload.status).to eq('Confirmed')
      inventory.reload
      expect(inventory.status).to eq('sold')
      expect(inventory.sale_order_id).to eq(order.id)
      expect(inventory.sold_price).to eq(100.0)
    end

    it 'is rejected when the order carries a received payment' do
      create(:payment, sale_order: order, amount: 100.0, status: 'Completed')
      status_before = order.reload.status

      patch "/api/v1/sales_orders/#{order.id}", params: { sales_order: { status: 'canceled' } }

      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(order.reload.status).to eq(status_before)
      expect(order.status).not_to eq('Canceled')
    end

    it 'still applies ordinary status changes' do
      patch "/api/v1/sales_orders/#{order.id}", params: { sales_order: { status: 'confirmed' } }

      expect(response).to have_http_status(:ok), response.body
      expect(order.reload.status).to eq('Confirmed')
    end
  end
end
