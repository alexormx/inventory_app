# frozen_string_literal: true

require 'rails_helper'

# Storefront authority across the cart stack: a visitor keeps the legacy
# session cart with all three persistence tables untouched; an authenticated
# customer's add, update, view, checkout entry and removal are persisted in
# the durable ACTIVE ShoppingCart and the session only mirrors it.
RSpec.describe 'Shopping cart persistence and the storefront', type: :request do
  let(:product) { create(:product) }

  def expect_persistence_empty
    expect(ShoppingCart.count).to eq(0)
    expect(ShoppingCartItem.count).to eq(0)
    expect(CartSessionImport.count).to eq(0)
  end

  def persisted_quantities
    ShoppingCartItem.pluck(:product_reference, :condition, :quantity).map { |r, c, q| [r, c, q] }
  end

  context 'anonymous visitor' do
    it 'keeps add, update, view, checkout entry and removal in the session cart only' do
      post cart_items_path, params: { product_id: product.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
      expect_persistence_empty

      put cart_item_path(product.id), params: { product_id: product.id, quantity: 2 }, as: :json
      expect(response).to have_http_status(:ok)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect_persistence_empty

      get cart_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.product_name)

      get checkout_step1_path
      expect(response).to redirect_to(new_user_session_path)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect_persistence_empty

      delete cart_item_path(product.id), params: { product_id: product.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(session[:cart]).to eq({})
      expect_persistence_empty
    end
  end

  context 'authenticated customer' do
    let(:user) { create(:user) }

    before { sign_in user }

    it 'persists add, update and removal in one ACTIVE cart and mirrors it into the session' do
      post cart_items_path, params: { product_id: product.id }, as: :json
      expect(response).to have_http_status(:ok)
      cart = user.shopping_carts.sole
      expect(cart.status).to eq('active')
      expect(persisted_quantities).to eq([[product.id, 'brand_new', 1]])
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })

      put cart_item_path(product.id), params: { product_id: product.id, quantity: 2 }, as: :json
      expect(response).to have_http_status(:ok)
      expect(persisted_quantities).to eq([[product.id, 'brand_new', 2]])
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })

      get cart_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.product_name)

      get checkout_step1_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.product_name)

      delete cart_item_path(product.id), params: { product_id: product.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(persisted_quantities).to eq([])
      expect(cart.reload.status).to eq('active')
      expect(session[:cart]).to eq({})
      expect(ShoppingCart.count).to eq(1)
      expect(CartSessionImport.count).to eq(0)
    end
  end
end
