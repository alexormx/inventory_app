# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CartItems', type: :request do
  let!(:product) { create(:product) }

  describe 'POST /cart_items' do
    it 'adds item to the cart with brand_new condition' do
      post cart_items_path, params: { product_id: product.id }
      expect(session[:cart][product.id.to_s]).to be_a(Hash)
      expect(session[:cart][product.id.to_s]['brand_new']).to eq(1)
    end

    it 'renders a successful Turbo Stream response when adding an item' do
      post cart_items_path,
           params: { product_id: product.id },
           headers: { 'ACCEPT' => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('action="append" target="flash-stack"')
      expect(response.body).to include(product.product_name)
      expect(response.body).to include('action="update" target="cart-count"')
      expect(session[:cart].dig(product.id.to_s, 'brand_new')).to eq(1)
    end

    it 'adds item with specific condition' do
      # Crear inventario disponible con condición misb (localizable = vendible)
      create(:inventory, product: product, status: :available, item_condition: :misb,
                         inventory_location: create(:inventory_location, :warehouse))
      post cart_items_path, params: { product_id: product.id, condition: 'misb' }
      expect(session[:cart][product.id.to_s]['misb']).to eq(1)
    end
  end

  describe 'PUT /cart_items/:id' do
    before { post cart_items_path, params: { product_id: product.id } }

    it 'updates quantity for condition' do
      put cart_item_path(product), params: { product_id: product.id, quantity: 3, condition: 'brand_new' }
      expect(session[:cart][product.id.to_s]['brand_new']).to eq(3)
    end

    it 'returns json with totals' do
      put cart_item_path(product),
          params: { product_id: product.id, quantity: 2, condition: 'brand_new' },
          headers: { 'ACCEPT' => 'application/json' }

      json = response.parsed_body
      expect(json['quantity']).to eq(2)
      expect(json['cart_total']).to be_present
      expect(json['total_items']).to eq(2)
      expect(json).to include(
        'item_immediate' => 2,
        'item_in_transit' => 0,
        'item_pending' => 0,
        'item_pending_type' => nil
      )
    end

    it 'returns a bounded error contract without success-only fields' do
      put cart_item_path(product),
          params: { product_id: product.id, quantity: 4, condition: 'brand_new' },
          headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json['error']).to eq('Máximo 3 unidades.')
      expect(json).not_to include('quantity', 'cart_total', 'line_total')
    end

    it 'renders a Turbo-visible alert when an update is rejected' do
      put cart_item_path(product),
          params: { product_id: product.id, quantity: 4, condition: 'brand_new' },
          headers: { 'ACCEPT' => Mime[:turbo_stream].to_s }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('Máximo 3 unidades.', 'alert-danger')
    end

    it 'keeps collectible transit in the line contract but out of the global pending summary' do
      collectible = create(:product, skip_seed_inventory: true, status: :active)
      create(:inventory, product: collectible, status: :in_transit, item_condition: :mint, selling_price: 20)
      post cart_items_path, params: { product_id: collectible.id, condition: 'mint' }

      put cart_item_path(collectible),
          params: { product_id: collectible.id, quantity: 1, condition: 'mint' },
          headers: { 'ACCEPT' => 'application/json' }

      json = response.parsed_body
      expect(json['summary_in_transit_total']).to eq(0)
      expect(json['summary_pending_total']).to eq(0)
      expect(json['item_in_transit']).to eq(1)
    end

    it 'keeps brand-new transit in the global pending summary' do
      transit_product = create(:product, skip_seed_inventory: true, status: :active)
      create(:inventory, product: transit_product, status: :in_transit, item_condition: :brand_new)
      post cart_items_path, params: { product_id: transit_product.id, condition: 'brand_new' }

      put cart_item_path(transit_product),
          params: { product_id: transit_product.id, quantity: 1, condition: 'brand_new' },
          headers: { 'ACCEPT' => 'application/json' }

      json = response.parsed_body
      expect(json['summary_in_transit_total']).to eq(1)
      expect(json['summary_pending_total']).to eq(1)
      expect(json['item_in_transit']).to eq(1)
    end
  end

  describe 'DELETE /cart_items/:id' do
    before { post cart_items_path, params: { product_id: product.id } }

    it 'removes item condition' do
      delete cart_item_path(product), params: { product_id: product.id, condition: 'brand_new' }
      expect(session[:cart][product.id.to_s]).to be_nil
    end

    it 'returns json after delete' do
      delete cart_item_path(product),
             params: { product_id: product.id, condition: 'brand_new' },
             headers: { 'ACCEPT' => 'application/json' }

      json = response.parsed_body
      expect(json['cart_total']).to be_present
      expect(json['total_items']).to eq(0)
    end

    it 'uses the reachable cart-row stream without replacing live-region roots' do
      remaining_product = create(:product)
      post cart_items_path, params: { product_id: remaining_product.id }

      delete cart_item_path(product),
             params: { product_id: product.id, condition: 'brand_new' },
             headers: {
               'ACCEPT' => Mime[:turbo_stream].to_s,
               'HTTP_REFERER' => cart_url
             }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="update" target="cart-total"')
      expect(response.body).to include('action="update" target="cart-count"')
      expect(response.body).to include('action="update" target="cart-status"')
      expect(response.body).to include('Producto eliminado. Total del carrito:')
      expect(response.body).to include('action="update" target="cart-pending-summary"')
      expect(response.body).not_to include('action="replace" target="cart-pending-summary"')
      expect(response.body).not_to include('action="update" target="cart-content"')
    end

    it 'replaces the cart content with a focusable empty state after the final removal' do
      delete cart_item_path(product),
             params: { product_id: product.id, condition: 'brand_new' },
             headers: {
               'ACCEPT' => Mime[:turbo_stream].to_s,
               'HTTP_REFERER' => cart_url
             }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="update" target="cart-content"')
      expect(response.body).to include('action="update" target="cart-status"')
      expect(response.body).to include('Carrito vacío.')
      expect(response.body).to include('id="cart-empty-cta"')
      expect(response.body).not_to include('target="cart-total"')
    end
  end
end
