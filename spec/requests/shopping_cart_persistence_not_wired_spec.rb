# frozen_string_literal: true

require 'rails_helper'

# PR A of the shopping cart persistence architecture is additive-only: the
# storefront must keep reading/writing session[:cart] via the existing Cart
# PORO exactly as before. No controller has been wired to ShoppingCart yet -
# that only happens once import/reconciliation exists in a later PR.
RSpec.describe 'Shopping cart persistence foundation is not wired into the storefront', type: :request do
  let(:product) { create(:product) }
  let(:customer) { create(:user) }

  it 'creates no ShoppingCart rows when adding, updating and removing cart items anonymously' do
    expect do
      post cart_items_path, params: { product_id: product.id }
      put cart_item_path(product.id), params: { product_id: product.id, quantity: 2 }
      get cart_path
      delete cart_item_path(product.id), params: { product_id: product.id }
    end.not_to change(ShoppingCart, :count)

    expect(ShoppingCartItem.count).to eq(0)
  end

  it 'creates no ShoppingCart rows for an authenticated customer using the cart' do
    sign_in customer

    expect do
      post cart_items_path, params: { product_id: product.id }
      get cart_path
    end.not_to change(ShoppingCart, :count)
  end

  it 'still uses session[:cart] as the source of truth for an anonymous visitor' do
    post cart_items_path, params: { product_id: product.id }

    expect(session[:cart][product.id.to_s]['brand_new']).to eq(1)
    expect(ShoppingCart.count).to eq(0)
  end

  it 'creates no ShoppingCart rows when visiting checkout' do
    sign_in customer
    post cart_items_path, params: { product_id: product.id }

    expect { get checkout_step1_path }.not_to change(ShoppingCart, :count)
  end
end
