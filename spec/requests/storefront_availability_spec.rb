# frozen_string_literal: true

require 'rails_helper'

# Regression cover for the catalog/cart availability divergence: the catalog
# aggregated physical stock by product_id alone (condition-blind) while the
# cart gate validated one specific condition, so a card could advertise
# "Agregar" for a product whose only piece was a collectible condition. The
# add posts no condition, the controller defaults to brand_new, and the add
# was rejected - catalog and cart disagreeing about the same product.
RSpec.describe 'Storefront availability', type: :request do
  let(:user)     { create(:user) }
  let(:location) { create(:inventory_location) }

  before do
    host! 'localhost'
    sign_in user
  end

  # The product factory seeds 5 located brand_new units by default, which
  # would mask every assertion here.
  def bare_product(**attrs)
    create(:product, skip_seed_inventory: true, **attrs)
  end

  def located_available(product, condition:, count: 1)
    count.times do
      create(:inventory, product: product, status: :available,
                         item_condition: condition, inventory_location: location)
    end
  end

  # A real in-transit piece belongs to a purchase order with an expected
  # delivery date - that ETA is what drives the catalog's "Reservar" CTA.
  def in_transit(product, condition:, count: 1)
    purchase_order = create(:purchase_order, expected_delivery_date: 5.days.from_now.to_date)
    count.times do
      create(:inventory, product: product, status: :in_transit,
                         item_condition: condition, purchase_order: purchase_order)
    end
  end

  def document
    Nokogiri::HTML(response.body)
  end

  # The card's direct add posts to /cart_items with no condition, so the
  # backend defaults to brand_new. Its presence is the claim "you can buy
  # brand_new right now".
  def direct_add_forms
    document.css("form[action='#{cart_items_path}']")
  end

  describe 'catalog card CTA' do
    it 'does not offer a direct brand_new add when only another condition is in stock' do
      product = bare_product
      located_available(product, condition: :mint)

      get catalog_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.product_name)
      expect(direct_add_forms).to be_empty
      expect(response.body).to include('Ver opciones')
      expect(response.body).to include('Disponible en otra condición')
    end

    it 'offers a direct add when brand_new is available now' do
      product = bare_product
      located_available(product, condition: :brand_new)

      get catalog_path

      expect(direct_add_forms).not_to be_empty
      expect(response.body).to include('Agregar')
      expect(response.body).not_to include('Ver opciones')
    end

    it 'keeps the in-transit reservation CTA and never calls it a normal add' do
      product = bare_product
      in_transit(product, condition: :brand_new)

      get catalog_path

      expect(response.body).to include('Reservar')
      expect(response.body).not_to include('Ver opciones')
    end

    it 'never offers an add when nothing is available or reservable' do
      product = bare_product
      create(:inventory, product: product, status: :available,
                         item_condition: :brand_new, inventory_location: nil)

      get catalog_path

      # Unlocated stock is not publishable and nothing else makes the product
      # orderable, so auto-pause takes it inactive and out of the catalog
      # entirely. The physical-location invariant is what drives that.
      expect(product.reload).not_to be_active
      expect(response.body).not_to include(product.product_name)
      expect(direct_add_forms).to be_empty
      expect(response.body).not_to include('Ver opciones')
    end
  end

  describe 'cart add' do
    it 'rejects a brand_new add when only another condition is in stock' do
      product = bare_product
      located_available(product, condition: :mint)

      post cart_items_path, params: { product_id: product.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ShoppingCartItem.count).to eq(0)
    end

    it 'accepts a brand_new add backed by located available stock' do
      product = bare_product
      located_available(product, condition: :brand_new)

      post cart_items_path, params: { product_id: product.id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(ShoppingCartItem.count).to eq(1)
    end

    it 'accepts the collectible condition that actually has stock' do
      product = bare_product
      located_available(product, condition: :mint)

      post cart_items_path, params: { product_id: product.id, condition: 'mint' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(ShoppingCartItem.last.condition).to eq('mint')
    end

    it 'does not let unlocated stock authorize an add' do
      product = bare_product
      create(:inventory, product: product, status: :available,
                         item_condition: :brand_new, inventory_location: nil)

      post cart_items_path, params: { product_id: product.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ShoppingCartItem.count).to eq(0)
    end
  end

  describe 'in-transit is future availability, not available now' do
    it 'reports the two concepts separately through the canonical facade' do
      product = bare_product
      in_transit(product, condition: :brand_new)

      result = Inventories::Availability.for(product, condition: 'brand_new')

      expect(result.available_now).to eq(0)
      expect(result.in_transit).to eq(1)
    end
  end

  describe 'in stock facet' do
    it 'counts only products with located available stock' do
      in_stock = bare_product
      located_available(in_stock, condition: :brand_new)
      transit_only = bare_product
      in_transit(transit_only, condition: :brand_new)

      get catalog_path, params: { in_stock: '1' }

      expect(response.body).to include(in_stock.product_name)
      expect(response.body).not_to include(transit_only.product_name)
    end
  end

  describe 'related products' do
    it 'agrees with the canonical facade about a collectible-only neighbour' do
      shown = bare_product(category: 'diecast', brand: 'Tomica')
      located_available(shown, condition: :brand_new)
      related = bare_product(category: 'diecast', brand: 'Tomica')
      located_available(related, condition: :mint)

      get product_path(shown)

      expect(response).to have_http_status(:ok)
      expect(Inventories::Availability.for(related, condition: 'brand_new').available_now).to eq(0)
    end
  end

  describe 'query count' do
    # Scoped to inventory queries on purpose. The catalog has a separate,
    # pre-existing SiteSetting.get N+1 (~9 settings lookups per card) which
    # this PR does not touch; counting total queries would measure that
    # instead of the availability preloading this PR is responsible for.
    def inventory_query_count(&block)
      count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:name] == 'SCHEMA'

        count += 1 if payload[:sql].to_s.include?('"inventories"')
      end
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
      count
    end

    def seed_two_condition_product
      product = bare_product
      located_available(product, condition: :brand_new)
      located_available(product, condition: :mint)
    end

    it 'does not issue per-card inventory queries as the catalog grows' do
      3.times { seed_two_condition_product }

      get catalog_path # warm lazily-loaded settings and schema
      small = inventory_query_count { get catalog_path }

      4.times { seed_two_condition_product }

      large = inventory_query_count { get catalog_path }

      expect(large).to eq(small)
    end
  end
end
