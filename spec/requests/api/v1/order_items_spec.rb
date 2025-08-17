require 'rails_helper'

RSpec.describe 'Api::V1 Order Items', type: :request do
  before do
    allow_any_instance_of(Api::V1::PurchaseOrderItemsController).to receive(:authenticate_with_token!).and_return(true)
    allow_any_instance_of(Api::V1::SaleOrderItemsController).to receive(:authenticate_with_token!).and_return(true)
  end

  let!(:user) { User.create!(email: 'buyer@example.com', password: 'password') }
  let!(:po) { PurchaseOrder.create!(user: user, order_date: Date.today, expected_delivery_date: Date.today + 7, subtotal: 0, total_order_cost: 0, shipping_cost: 0, tax_cost: 0, other_cost: 0, currency: 'MXN', status: 'Pending') }
  let!(:so_user) { User.create!(email: 'customer@example.com', password: 'password') }
  let!(:so) { SaleOrder.create!(user: so_user, order_date: Date.today, subtotal: 0, tax_rate: 0, total_tax: 0, total_order_value: 0, discount: 0, status: 'Pending') }
  let!(:product) { Product.create!(product_sku: 'SKU-1', product_name: 'X', brand: 'B', category: 'C', selling_price: 10, maximum_discount: 0, minimum_price: 1) }

  it 'creates purchase order items and then sale order items reserving inventory' do
    post '/api/v1/purchase_order_items', params: { purchase_order_item: { purchase_order_id: po.id, product_sku: product.product_sku, quantity: 3, unit_cost: 5, unit_compose_cost_in_mxn: 5 } }
    expect(response).to have_http_status(:created)

    # batch create more
    post '/api/v1/purchase_order_items/batch', params: { purchase_order_id: po.id, items: [ { product_sku: product.product_sku, quantity: 2, unit_cost: 6 } ] }
    expect(response.status).to be_between(201, 422)

    # Now create one sale order item for 4 units, should reserve from inventory
    post '/api/v1/sale_order_items', params: { sale_order_item: { sale_order_id: so.id, product_sku: product.product_sku, quantity: 4, unit_cost: 10, unit_final_price: 10 } }
    expect(response).to have_http_status(:created)

    expect(Inventory.where(product_id: product.id, sale_order_id: so.id, status: :reserved).count).to eq(4)
  end
end
