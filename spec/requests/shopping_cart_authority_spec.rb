# frozen_string_literal: true

require 'rails_helper'

# The Phase B limitation is gone: once authenticated, the durable cart is the
# authority, every storefront mutation lands there, and a later session
# (same or another browser) sees exactly the committed state.
RSpec.describe 'Persistent cart authority for authenticated customers', type: :request do
  let(:password) { 'password123' }
  let(:user) { create(:user, password: password) }
  let(:product) { create(:product) }
  let(:other_product) { create(:product) }

  def log_in(account = user)
    post user_session_path, params: { user: { email: account.email, password: password } }
  end

  def log_out
    delete destroy_user_session_path
  end

  def lines
    ShoppingCartItem.joins(:shopping_cart).where(shopping_carts: { status: 'active', user_id: user.id })
                    .pluck(:product_reference, :condition, :quantity).map { |r, c, q| [r, c, q] }.sort
  end

  describe 'the former stale-cart limitation' do
    it 'remove after login -> logout -> fresh login does NOT resurrect the item' do
      post cart_items_path, params: { product_id: product.id }
      post cart_items_path, params: { product_id: other_product.id }
      log_in
      expect(lines).to contain_exactly([other_product.id, 'brand_new', 1], [product.id, 'brand_new', 1])

      delete cart_item_path(product.id), params: { product_id: product.id }
      expect(lines).to eq([[other_product.id, 'brand_new', 1]])

      log_out
      expect(session[:cart]).to be_nil

      log_in
      expect(session[:cart]).to eq(other_product.id.to_s => { 'brand_new' => 1 })
      get cart_path
      expect(response.body).to include("cart_item_#{other_product.id}_brand_new")
      expect(response.body).not_to include("cart_item_#{product.id}_brand_new")
      expect(lines).to eq([[other_product.id, 'brand_new', 1]])
    end

    it 'a quantity change after login survives logout and a fresh login' do
      post cart_items_path, params: { product_id: product.id }
      log_in
      put cart_item_path(product.id), params: { product_id: product.id, quantity: 3 }
      expect(lines).to eq([[product.id, 'brand_new', 3]])

      log_out
      log_in
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 3 })
    end

    it 'an item added after login is visible from another browser' do
      log_in
      post cart_items_path, params: { product_id: product.id }

      other_browser = open_session
      other_browser.post user_session_path, params: { user: { email: user.email, password: password } }
      other_browser.get cart_path
      expect(other_browser.response.body).to include(product.product_name)
      expect(other_browser.session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
    end
  end

  describe 'multi-session consistency' do
    it 'browser B sees browser A changes on its next request, and vice versa, with no resurrection' do
      a = open_session
      b = open_session
      [a, b].each { |s| s.post user_session_path, params: { user: { email: user.email, password: password } } }

      a.post cart_items_path, params: { product_id: product.id }
      b.get cart_path
      expect(b.response.body).to include("cart_item_#{product.id}_brand_new")

      b.delete cart_item_path(product.id), params: { product_id: product.id }
      a.get cart_path
      expect(a.response.body).not_to include("cart_item_#{product.id}_brand_new")
      expect(a.session[:cart]).to eq({})
      expect(lines).to eq([])

      a.post cart_items_path, params: { product_id: other_product.id }
      b.put cart_item_path(other_product.id), params: { product_id: other_product.id, quantity: 2 }
      a.get cart_path
      expect(a.session[:cart]).to eq(other_product.id.to_s => { 'brand_new' => 2 })
    end
  end

  describe 'business rules and error semantics' do
    before { log_in }

    it 'keeps the storefront cap on the durable cart' do
      Cart::MAX_NEW_ITEMS_PER_PRODUCT.times { post cart_items_path, params: { product_id: product.id }, as: :json }
      post cart_items_path, params: { product_id: product.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(lines).to eq([[product.id, 'brand_new', Cart::MAX_NEW_ITEMS_PER_PRODUCT]])

      put cart_item_path(product.id), params: { product_id: product.id, quantity: 9 }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(lines).to eq([[product.id, 'brand_new', Cart::MAX_NEW_ITEMS_PER_PRODUCT]])
    end

    it 'never reports success when the durable mutation cannot commit' do
      allow(ShoppingCarts::ActiveCartMutation).to receive(:add)
        .and_return(ShoppingCarts::ActiveCartMutation::Result.new(status: :retry_exhausted))

      post cart_items_path, params: { product_id: product.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
      expect(lines).to eq([])
      expect(session[:cart]).to eq({})
    end

    it 'adding to the cart reserves no inventory' do
      product # seed its inventory before taking the baseline
      before = Inventory.pluck(:id, :status, :sale_order_id).sort
      post cart_items_path, params: { product_id: product.id }
      expect(Inventory.pluck(:id, :status, :sale_order_id).sort).to eq(before)
    end
  end

  describe 'authorization' do
    it 'a customer can only ever mutate their own active cart' do
      stranger = create(:user, password: password)
      stranger_cart = create(:shopping_cart, user: stranger)
      create(:shopping_cart_item, shopping_cart: stranger_cart, product: product, quantity: 1)

      log_in
      post cart_items_path, params: { product_id: product.id, shopping_cart_id: stranger_cart.id, cart_id: stranger_cart.id }
      delete cart_item_path(product.id), params: { product_id: product.id, shopping_cart_id: stranger_cart.id }

      expect(stranger_cart.reload.shopping_cart_items.pluck(:product_reference, :quantity)).to eq([[product.id, 1]])
      expect(lines).to eq([])
      get cart_path
      expect(response.body).not_to include("cart_item_#{product.id}_brand_new")
    end
  end
end
