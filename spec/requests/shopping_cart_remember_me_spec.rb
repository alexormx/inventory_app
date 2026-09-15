# frozen_string_literal: true

require 'rails_helper'

# The remember-me strategy establishes a session through Warden#set_user with
# event :authentication on an ordinary request, without any login form. The
# same hook must reconcile there: the durable cart is restored into the new
# session, and nothing is imported twice.
RSpec.describe 'Persistent cart and remember-me re-authentication', type: :request do
  let(:password) { 'password123' }
  let(:user) { create(:user, password: password) }
  let(:product) { create(:product) }

  it 'restores the durable cart into a fresh session authenticated by the remember cookie' do
    post cart_items_path, params: { product_id: product.id }
    post user_session_path, params: { user: { email: user.email, password: password, remember_me: '1' } }
    expect(response).to have_http_status(:redirect)
    cart = user.shopping_carts.sole
    expect(cookies['remember_user_token']).to be_present

    # The browser is closed: the (non-persistent) session cookie is gone, the remember cookie stays.
    cookies.delete(Rails.application.config.session_options[:key])

    get cart_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("cart_item_#{product.id}_brand_new")
    expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
    expect(session[:cart_reconciled]).to include('cart_id' => cart.id)
    expect(cart.shopping_cart_items.pluck(:product_reference, :quantity)).to eq([[product.id, 1]])
    expect(CartSessionImport.count).to eq(1)

    # And a storefront mutation on that re-authenticated session is durable.
    delete cart_item_path(product.id), params: { product_id: product.id }
    expect(cart.shopping_cart_items.count).to eq(0)
  end
end
