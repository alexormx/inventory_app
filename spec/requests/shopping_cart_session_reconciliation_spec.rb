# frozen_string_literal: true

require 'rails_helper'

# End-to-end through the real Devise/Warden flow: the browser cart lives in the
# cookie session, authentication triggers exactly one reconciliation, the
# session is rehydrated, and the storefront keeps working from the session.
RSpec.describe 'Session cart reconciliation at authentication', type: :request do
  let(:password) { 'password123' }
  let(:user) { create(:user, password: password) }
  let(:product) { create(:product) }
  let(:other_product) { create(:product) }

  def log_in(account = user, password: self.password)
    post user_session_path, params: { user: { email: account.email, password: password } }
  end

  def log_out
    delete destroy_user_session_path
  end

  def quantities(cart)
    cart.shopping_cart_items.reload.to_h { |i| [[i.product_reference, i.condition], i.quantity] }
  end

  def expect_persistence_empty
    expect(ShoppingCart.count).to eq(0)
    expect(ShoppingCartItem.count).to eq(0)
    expect(CartSessionImport.count).to eq(0)
  end

  describe 'guest cart -> successful login' do
    it 'imports the session cart once, records a receipt and rehydrates the session' do
      post cart_items_path, params: { product_id: product.id }
      post cart_items_path, params: { product_id: product.id }
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect_persistence_empty

      log_in
      expect(response).to redirect_to(root_path)

      cart = user.shopping_carts.sole
      expect(cart.status).to eq('active')
      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 2)
      expect(CartSessionImport.sole.shopping_cart).to eq(cart)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect(session[:cart_reconciled]).to include('cart_id' => cart.id)

      get cart_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.product_name)
    end

    it 'does not double quantities when the login/reconciliation path runs again' do
      post cart_items_path, params: { product_id: product.id }
      log_in
      cart = user.shopping_carts.sole

      # Same browser session, authentication event fired again (e.g. a retried
      # login request, or the remember-me strategy re-authenticating).
      sign_in user
      get cart_path
      expect(response).to have_http_status(:ok)

      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 1)
      expect(CartSessionImport.count).to eq(1)
      expect(ShoppingCart.count).to eq(1)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
    end

    it 'does not double quantities when the browser retries the login POST after a lost response' do
      cookie_key = Rails.application.config.session_options[:key]
      browser = open_session
      browser.post cart_items_path, params: { product_id: product.id }
      stale_cookie = browser.cookies[cookie_key]

      # The response of the first login never reaches the browser...
      browser.post user_session_path, params: { user: { email: user.email, password: password } }
      cart = user.shopping_carts.sole
      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 1)

      # ...so it retries with the cookie it still has: the pre-login cart + the same session id.
      retry_browser = open_session
      retry_browser.cookies[cookie_key] = stale_cookie
      retry_browser.post user_session_path, params: { user: { email: user.email, password: password } }
      expect(retry_browser.response).to have_http_status(:redirect)
      expect(retry_browser.response.location).to end_with(root_path)

      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 1)
      expect(CartSessionImport.count).to eq(1)
      expect(ShoppingCart.count).to eq(1)
      expect(retry_browser.session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
    end
  end

  describe 're-authentication after storefront edits in the same browser session' do
    it 'neither doubles the persisted lines nor loses the edits' do
      post cart_items_path, params: { product_id: product.id }
      log_in
      cart = user.shopping_carts.sole

      post cart_items_path, params: { product_id: other_product.id } # session-only edit after hydration
      sign_in user                                                   # e.g. remember-me re-authenticating
      get cart_path
      expect(response).to have_http_status(:ok)

      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 1)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 }, other_product.id.to_s => { 'brand_new' => 1 })
      expect(CartSessionImport.count).to eq(1)
    end
  end

  describe 'other ways of establishing a session' do
    it 'reconciles after a password reset signs the user in' do
      post cart_items_path, params: { product_id: product.id }
      raw_token = user.send_reset_password_instructions

      put user_password_path, params: {
        user: { reset_password_token: raw_token, password: 'newpassword123', password_confirmation: 'newpassword123' }
      }
      expect(response).to have_http_status(:redirect)

      cart = user.shopping_carts.sole
      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 1)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
      expect(session[:cart_reconciled]).to include('cart_id' => cart.id)
    end

    it 'never imports for an unconfirmed account, whose login is rejected' do
      unconfirmed = create(:user, password: password, confirmed_at: nil)
      post cart_items_path, params: { product_id: product.id }

      log_in(unconfirmed)

      get profile_path
      expect(response).to redirect_to(new_user_session_path)
      expect_persistence_empty
    end
  end

  describe 'failed login' do
    it 'never imports' do
      post cart_items_path, params: { product_id: product.id }

      log_in(password: 'wrong')

      expect_persistence_empty
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
    end
  end

  describe 'existing persistent cart' do
    let!(:cart) { create(:shopping_cart, user: user) }

    before { create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 2) }

    it 'restores it into an empty browser session without recording an import' do
      log_in

      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect(CartSessionImport.count).to eq(0)
      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 2)

      get cart_path
      expect(response.body).to include(product.product_name)
    end

    it 'merges browser contents into it and rehydrates the union' do
      post cart_items_path, params: { product_id: product.id }
      post cart_items_path, params: { product_id: other_product.id }

      log_in

      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 3, [other_product.id, 'brand_new'] => 1)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 3 }, other_product.id.to_s => { 'brand_new' => 1 })
      expect(ShoppingCart.count).to eq(1)
      expect(CartSessionImport.count).to eq(1)
    end
  end

  describe 'logout / login again' do
    it 'keeps quantities stable across a logout and a fresh login with no browser changes' do
      post cart_items_path, params: { product_id: product.id }
      log_in
      cart = user.shopping_carts.sole

      log_out
      expect(session[:cart]).to be_nil # Devise reset the session

      log_in
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 1)
      expect(CartSessionImport.count).to eq(1)
      expect(ShoppingCart.count).to eq(1)
    end
  end

  describe 'different user on the same browser' do
    let(:other_user) { create(:user, password: password) }

    it 'gives the second user their own cart and never exposes or re-applies the first user cart' do
      post cart_items_path, params: { product_id: product.id }
      log_in
      cart_a = user.shopping_carts.sole

      log_out
      post cart_items_path, params: { product_id: other_product.id }
      log_in(other_user)

      cart_b = other_user.shopping_carts.sole
      expect(cart_b).not_to eq(cart_a)
      expect(quantities(cart_b)).to eq([other_product.id, 'brand_new'] => 1)
      expect(quantities(cart_a)).to eq([product.id, 'brand_new'] => 1)
      expect(session[:cart]).to eq(other_product.id.to_s => { 'brand_new' => 1 })
      expect(CartSessionImport.count).to eq(2)
      expect(CartSessionImport.all.map(&:shopping_cart)).to contain_exactly(cart_a, cart_b)
    end
  end

  describe 'a recoverable cart problem' do
    it 'never breaks authentication' do
      allow(ShoppingCarts::SessionReconciler).to receive(:call).and_raise(ActiveRecord::StatementInvalid, 'boom')
      post cart_items_path, params: { product_id: product.id }

      log_in
      expect(response).to redirect_to(root_path)

      get profile_path
      expect(response).to have_http_status(:ok)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
      expect_persistence_empty
    end
  end

  describe 'storefront non-interference after reconciliation' do
    it 'keeps add, update, view, checkout entry and removal on the session, never on the persistent cart' do
      post cart_items_path, params: { product_id: product.id }
      log_in
      cart = user.shopping_carts.sole
      persisted_before = [quantities(cart), CartSessionImport.count, ShoppingCart.count]

      post cart_items_path, params: { product_id: other_product.id }, as: :json
      expect(response).to have_http_status(:ok)
      put cart_item_path(product.id), params: { product_id: product.id, quantity: 3 }, as: :json
      expect(response).to have_http_status(:ok)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 3 }, other_product.id.to_s => { 'brand_new' => 1 })

      get cart_path
      expect(response).to have_http_status(:ok)
      get checkout_step1_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.product_name)

      delete cart_item_path(other_product.id), params: { product_id: other_product.id }, as: :json
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 3 })

      expect([quantities(cart), CartSessionImport.count, ShoppingCart.count]).to eq(persisted_before)
    end
  end

  describe 'anonymous browsing' do
    it 'never creates persistent carts' do
      post cart_items_path, params: { product_id: product.id }
      get cart_path
      get root_path
      expect_persistence_empty
    end
  end
end
