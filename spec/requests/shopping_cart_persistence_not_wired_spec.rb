# frozen_string_literal: true

require 'rails_helper'

# The foundation must remain additive: exercise successful session-cart actions
# for both identities, including checkout entry, with all three new tables empty.
RSpec.describe 'Shopping cart persistence foundation is not wired into the storefront', type: :request do
  let(:product) { create(:product) }

  [false, true].each do |authenticated|
    context(authenticated ? 'authenticated customer' : 'anonymous visitor') do
      before { sign_in create(:user) if authenticated }

      it 'keeps add, update, view, checkout entry and removal in the session cart' do
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
        expect_persistence_empty

        get checkout_step1_path
        if authenticated
          expect(response).to have_http_status(:ok)
          expect(response.body).to include(product.product_name)
        else
          expect(response).to redirect_to(new_user_session_path)
        end
        expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
        expect_persistence_empty

        delete cart_item_path(product.id), params: { product_id: product.id }, as: :json
        expect(response).to have_http_status(:ok)
        expect(session[:cart]).to eq({})
        expect_persistence_empty
      end
    end
  end

  def expect_persistence_empty
    expect(ShoppingCart.count).to eq(0)
    expect(ShoppingCartItem.count).to eq(0)
    expect(CartSessionImport.count).to eq(0)
  end
end
