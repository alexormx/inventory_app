# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Checkouts", type: :request do
  let!(:user) { create(:user) }
  let!(:product) { create(:product, selling_price: 10.0, minimum_price: 5.0) }
  let!(:address) { create(:shipping_address, user: user, default: true) }
  let!(:payment_method) { create(:payment_method, code: 'efectivo', name: 'Efectivo', active: true) }
  let!(:shipping_method) { create(:shipping_method, :standard) }

  before do
    sign_in user
  end

  it "creates a sale order and clears the cart" do
    # Add product to cart
    post cart_items_path, params: { product_id: product.id }
    expect(response).to have_http_status(:redirect)

    # Step 2: select shipping address and method
    post checkout_step2_path, params: {
      selected_address_id: address.id,
      shipping_method: 'standard'
    }
    expect(response).to redirect_to(checkout_step3_path)

    # Step 3: access page to generate checkout token
    get checkout_step3_path
    expect(response).to have_http_status(:success)

    # Extract checkout token from the response body (it's in a hidden field)
    checkout_token = response.body[/name="checkout_token"[^>]*value="([^"]+)"/, 1]
    expect(checkout_token).to be_present

    # Complete checkout
    expect {
      post checkout_complete_path, params: {
        payment_method: 'efectivo',
        checkout_token: checkout_token,
        accept_pending: '1'
      }
    }.to change(SaleOrder, :count).by(1)

    # Verify redirect to thank you page
    expect(response).to redirect_to(/checkout\/thank_you/)

    sale_order = SaleOrder.last
    expect(sale_order.sale_order_items.count).to eq(1)
    expect(sale_order.subtotal).to eq(10.0)
  end

  it 'identifies inventory already in transit as awaiting arrival on the review page' do
    product.inventories.destroy_all
    create(:inventory, product: product, status: :in_transit)
    product.update!(status: 'active')

    post cart_items_path, params: { product_id: product.id }
    post checkout_step2_path, params: {
      selected_address_id: address.id,
      shipping_method: shipping_method.code
    }
    get checkout_step3_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include('1 en tránsito')
    expect(response.body).to include('pendiente de llegada')
  end

  it 'does not offer or accept an active payment method unsupported by Payment' do
    unsupported = create(:payment_method, code: 'custom_gateway', name: 'Pasarela personalizada', active: true)
    post cart_items_path, params: { product_id: product.id }
    post checkout_step2_path, params: {
      selected_address_id: address.id,
      shipping_method: shipping_method.code
    }
    get checkout_step3_path

    expect(response.body).not_to include(unsupported.name)

    expect do
      post checkout_complete_path, params: {
        payment_method: unsupported.code,
        checkout_token: session[:checkout_token]
      }
    end.not_to change(SaleOrder, :count)

    expect(response).to redirect_to(checkout_step3_path)
    expect(flash[:alert]).to match(/método de pago inválido/i)
  end

  context 'when the selected shipping method becomes inactive' do
    before do
      post cart_items_path, params: { product_id: product.id }
      post checkout_step2_path, params: {
        selected_address_id: address.id,
        shipping_method: shipping_method.code
      }
      get checkout_step3_path
      shipping_method.update!(active: false)
    end

    it 'returns from the review page to shipping selection' do
      get checkout_step3_path

      expect(response).to redirect_to(checkout_step2_path)
      expect(flash[:alert]).to match(/método de envío/i)
    end

    it 'rejects final submission without creating an order' do
      expect do
        post checkout_complete_path, params: {
          payment_method: payment_method.code,
          checkout_token: session[:checkout_token]
        }
      end.not_to change(SaleOrder, :count)

      expect(response).to redirect_to(checkout_step2_path)
      expect(flash[:alert]).to match(/método de envío/i)
    end
  end
end
