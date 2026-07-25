# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Checkout confirmation', type: :request do
  let(:user) { create(:user) }
  let(:product) { create(:product, selling_price: 116.00, average_purchase_cost: 70.00) }
  let(:order) do
    create(
      :sale_order,
      user: user,
      subtotal: 116.00,
      shipping_cost: 99.00,
      total_order_value: 215.00
    )
  end

  before do
    create(
      :sale_order_item,
      sale_order: order,
      product: product,
      unit_cost: 70.00,
      unit_selling_price: 116.00,
      unit_final_price: 116.00,
      total_line_cost: 116.00
    )
    create(:order_shipping_address, sale_order: order, shipping_method: 'envio_estandar')
    create(:payment, sale_order: order, amount: 215.00, status: 'Pending')
    create(:shipping_method, code: 'envio_estandar', name: 'Envío estándar', base_cost: 99.00)
    sign_in user
  end

  it 'renders the persisted order, address, shipping, line, and totals' do
    get checkout_thank_you_path(order_id: order.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order.id)
    expect(response.body).to include('John Doe')
    expect(response.body).to include('Envío estándar')
    expect(response.body).to include(product.product_name)
    expect(response.body).to include('$116.00')
    expect(response.body).to include('$215.00')
    expect(response.body).to include(catalog_path)
    expect(response.body).to include(orders_path)
  end

  it 'shows a completed persisted payment as paid' do
    order.payments.last.update!(status: 'Completed')

    get checkout_thank_you_path(order_id: order.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Pagado')
    expect(response.body).not_to include('Pendiente')
  end

  it 'identifies pre-reserved inventory as awaiting arrival on confirmation and order detail' do
    item = order.sale_order_items.sole
    create(
      :inventory,
      product: product,
      status: :pre_reserved,
      sale_order: order,
      sale_order_item: item
    )

    get checkout_thank_you_path(order_id: order.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('En tránsito')
    expect(response.body).to include('Pendiente de llegada')

    get order_path(order)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('En tránsito: 1')
    expect(response.body).to include('pendiente de llegada')
    expect(response.body).to include('order-unit-price d-none d-sm-table-cell')
    expect(response.body).to include('order-mobile-unit-price d-sm-none')
  end
end
