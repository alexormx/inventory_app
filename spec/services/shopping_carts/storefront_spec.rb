# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::Storefront do
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:other) { create(:product, skip_seed_inventory: true) }
  let(:marker_key) { ShoppingCarts::AuthenticationHandoff::MARKER_KEY }

  describe 'anonymous' do
    let(:session) { {} }
    let(:storefront) { described_class.for(user: nil, session: session) }

    it 'wraps the legacy session cart and enforces the same caps' do
      expect(storefront.persistent_cart).to be_nil
      expect(storefront.add(product, 'brand_new')).to eq(:ok)
      expect(storefront.set_quantity(product, 'brand_new', 3)).to eq(:ok)
      expect(storefront.set_quantity(product, 'brand_new', 4)).to eq(:limit_exceeded)
      expect(storefront.add(product, 'brand_new')).to eq(:limit_exceeded)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 3 })
      expect(storefront.remove(product, condition: 'brand_new')).to eq(:ok)
      expect(session[:cart]).to eq({})
      expect(ShoppingCart.count).to eq(0)
    end
  end

  describe 'authenticated' do
    let(:user) { create(:user) }
    let(:session) { {} }
    let(:storefront) { described_class.for(user: user, session: session) }

    it 'reads the durable cart and mirrors it into the session with a marker' do
      cart = create(:shopping_cart, user: user)
      create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 2)

      expect(storefront.persistent_cart).to eq(cart)
      expect(storefront.cart.quantity_for(product.id)).to eq(2)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect(session[marker_key]).to include('cart_id' => cart.id)
    end

    it 'commits every mutation durably and re-projects the committed state' do
      expect(storefront.add(product, 'brand_new')).to eq(:ok)
      expect(storefront.add(other, 'misb')).to eq(:ok)
      expect(storefront.set_quantity(product, 'brand_new', 2)).to eq(:ok)

      cart = user.shopping_carts.sole
      expect(cart.shopping_cart_items.pluck(:product_reference, :quantity)).to contain_exactly([product.id, 2], [other.id, 1])
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 }, other.id.to_s => { 'misb' => 1 })
      expect(storefront.cart.item_count).to eq(3)

      expect(storefront.remove(other)).to eq(:ok)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect(storefront.cart.item_count).to eq(2)
    end

    it 'does not report success when the durable mutation cannot commit' do
      allow(ShoppingCarts::ActiveCartMutation).to receive(:add)
        .and_return(ShoppingCarts::ActiveCartMutation::Result.new(status: :retry_exhausted))

      expect(storefront.add(product, 'brand_new')).to eq(:retry_exhausted)
      expect(session[:cart]).to be_nil
    end

    it 'shows durable state on every fresh facade, so another device sees committed changes' do
      described_class.for(user: user, session: {}).add(product, 'brand_new')

      other_device = described_class.for(user: user, session: {})
      expect(other_device.cart.quantity_for(product.id)).to eq(1)
    end

    context 'with an unreconciled browser cart in the session (no marker)' do
      let(:session) do
        Class.new(Hash) do
          def id
            Rack::Session::SessionId.new(SecureRandom.hex(16))
          end
        end.new.merge!(cart: { product.id.to_s => { 'brand_new' => 2 } })
      end

      it 'reconciles it late, exactly once, then projects the durable cart' do
        expect(storefront.cart.quantity_for(product.id)).to eq(2)

        cart = user.shopping_carts.sole
        expect(cart.shopping_cart_items.pluck(:product_reference, :quantity)).to eq([[product.id, 2]])
        expect(CartSessionImport.count).to eq(1)
        expect(session[marker_key]).to include('cart_id' => cart.id)

        again = described_class.for(user: user, session: session)
        expect(again.cart.quantity_for(product.id)).to eq(2)
        expect(CartSessionImport.count).to eq(1)
      end

      it 'never wipes the cookie cart when the late reconciliation fails' do
        allow(ShoppingCarts::SessionReconciler).to receive(:call).and_raise(ActiveRecord::StatementInvalid, 'boom')

        expect(storefront.cart.empty?).to be(true)
        expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
        expect(session).not_to have_key(marker_key)
        expect(ShoppingCart.count).to eq(0)
      end
    end

    it 'never writes a stale bound session back over newer durable state' do
      cart = create(:shopping_cart, user: user)
      create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 1)
      # This browser's cookie still shows an older, larger cart; another device already changed it.
      session[:cart] = { product.id.to_s => { 'brand_new' => 3 }, other.id.to_s => { 'brand_new' => 2 } }
      session[marker_key] = { 'cart_id' => cart.id, 'digest' => 'stale' }

      expect(storefront.cart.quantity_for(product.id)).to eq(1)
      expect(storefront.cart.quantity_for(other.id)).to eq(0)
      expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
      expect(cart.shopping_cart_items.pluck(:product_reference, :quantity)).to eq([[product.id, 1]])
      expect(CartSessionImport.count).to eq(0)
    end

    it 'projects an empty session cart (with a marker) when the durable cart does not fit the cookie' do
      cart = create(:shopping_cart, user: user)
      create_list(:product, 120, skip_seed_inventory: true).each do |p|
        create(:shopping_cart_item, shopping_cart: cart, product: p, quantity: 1)
      end
      session[marker_key] = { 'cart_id' => cart.id, 'digest' => 'x' }

      expect(storefront.cart.items.size).to eq(120)
      expect(session[:cart]).to eq({})
      expect(session[marker_key]).to include('cart_id' => cart.id)
    end
  end
end
