# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API v1 products (read)', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:token) { ApiKey.generate!(name: 'KataFrame', scopes: ['products:read'], created_by: admin).last }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }

  let(:expected_keys) do
    %w[id code product_name brand category series scale selling_price description status
                     barcode launch_date stock_available publishable inventory badge tags length_cm width_cm height_cm weight_gr
                     custom_attributes image_urls updated_at]
  end

  def json
    JSON.parse(response.body)
  end

  def product(**attrs)
    create(:product, skip_seed_inventory: true, **attrs)
  end

  describe 'GET /api/v1/products' do
    it 'lists draft, inactive and active products, each with its status' do
      draft = product(status: 'draft')
      inactive = product(status: 'inactive')
      active = product(status: 'active', preorder_available: true)

      get '/api/v1/products', headers: headers

      expect(response).to have_http_status(:ok)
      statuses = json['items'].to_h { |item| [item['id'], item['status']] }
      expect(statuses).to include(draft.id => 'draft', inactive.id => 'inactive', active.id => 'active')
    end

    it 'returns exactly the whitelisted keys' do
      product
      get '/api/v1/products', headers: headers
      expect(json['items'].first.keys).to match_array(expected_keys)
    end

    it 'never exposes supplier identifiers or costs' do
      record = product(product_sku: 'SECRET-SKU-123', supplier_product_code: 'SECRET-SUPPLIER-456')
      record.update_columns(average_purchase_cost: 77.77)

      get '/api/v1/products', headers: headers
      list_body = response.body
      get "/api/v1/products/#{record.id}", headers: headers

      [list_body, response.body].each do |body|
        expect(body).not_to include('SECRET-SKU-123', 'SECRET-SUPPLIER-456', 'product_sku',
                                    'supplier_product_code', 'average_purchase_cost', '77.77')
      end
    end

    it 'lists image_urls primary first, as absolute URLs of the originals' do
      record = product
      second = record.ordered_product_images.last
      record.set_primary_product_image!(second.id)

      get "/api/v1/products/#{record.id}", headers: headers

      urls = json['image_urls']
      expect(urls.size).to eq(2)
      expect(urls).to all(start_with('http'))
      expect(urls.join).not_to include('variants', 'representations')
      expect(urls.first).to include(second.blob.signed_id)
    end

    it 'reports stock_available as free pieces available with a location' do
      record = product
      location = create(:inventory_location)
      2.times { Inventory.create!(product: record, purchase_cost: 10, status: :available, inventory_location: location) }
      Inventory.create!(product: record, purchase_cost: 10, status: :available) # sin ubicación: no cuenta

      get "/api/v1/products/#{record.id}", headers: headers
      expect(json['stock_available']).to eq(2)
    end

    it 'breaks the inventory down by status, with a total of pieces still in the store' do
      record = product
      location = create(:inventory_location)
      2.times { Inventory.create!(product: record, purchase_cost: 10, status: :available, inventory_location: location) }
      Inventory.create!(product: record, purchase_cost: 10, status: :in_transit)
      Inventory.create!(product: record, purchase_cost: 10, status: :damaged)
      Inventory.create!(product: record, purchase_cost: 10, status: :sold)
      Inventory.where(product: record, status: :available).first.update_columns(status: Inventory.statuses[:reserved])

      get "/api/v1/products/#{record.id}", headers: headers

      inventory = json['inventory']
      expect(inventory.keys).to match_array(%w[total] + Inventory.statuses.keys)
      expect(inventory).to include('available' => 1, 'reserved' => 1, 'in_transit' => 1, 'damaged' => 1,
                                   'sold' => 1, 'lost' => 0, 'pre_reserved' => 0)
      expect(inventory['total']).to eq(4) # vendidas no cuentan
    end

    it 'reports the inventory per product in the listing' do
      with_stock = product
      empty = product
      Inventory.create!(product: with_stock, purchase_cost: 10, status: :in_transit)

      get '/api/v1/products', headers: headers

      by_id = json['items'].to_h { |item| [item['id'], item['inventory']] }
      expect(by_id[with_stock.id]).to include('in_transit' => 1, 'total' => 1)
      expect(by_id[empty.id]).to include('total' => 0, 'available' => 0)
    end

    it 'sends the storefront badge as text, or null when none applies' do
      fresh = product
      fresh.update_columns(first_published_at: 1.day.ago)
      plain = product
      plain.update_columns(first_published_at: 1.year.ago, republished_at: nil, restocked_at: nil)

      get '/api/v1/products', headers: headers

      badges = json['items'].to_h { |item| [item['id'], item['badge']] }
      expect(badges[fresh.id]).to eq('Recién llegado')
      expect(badges[plain.id]).to be_nil
    end

    it 'sends the SEO keywords as tags, without blanks' do
      record = product
      record.update_columns(seo_keywords: ['tomica', ' skyline ', '', nil])

      get "/api/v1/products/#{record.id}", headers: headers
      expect(json['tags']).to eq(%w[tomica skyline])
    end

    describe 'publishability' do
      let!(:with_stock) { product.tap { |p| Inventory.create!(product: p, purchase_cost: 10, status: :in_transit) } }
      let!(:on_preorder) { product(preorder_available: true) }
      let!(:unlocated) { product.tap { |p| Inventory.create!(product: p, purchase_cost: 10, status: :available) } }
      let!(:bare) { product(status: 'draft') }

      def ids_in_response
        json['items'].map { |item| item['id'] }
      end

      it 'flags each product with the same rule the admin uses to publish' do
        get '/api/v1/products', headers: headers

        flags = json['items'].to_h { |item| [item['id'], item['publishable']] }
        expect(flags).to eq(with_stock.id => true, on_preorder.id => true, unlocated.id => false, bare.id => false)
        [with_stock, on_preorder, unlocated, bare].each do |record|
          expect(flags[record.id]).to eq(record.reload.eligible_for_publication?)
        end
      end

      it 'lists only publishable products with ?publishable=true' do
        get '/api/v1/products', params: { publishable: 'true' }, headers: headers
        expect(ids_in_response).to contain_exactly(with_stock.id, on_preorder.id)
      end

      it 'lists only unpublishable products with ?publishable=false' do
        get '/api/v1/products', params: { publishable: 'false' }, headers: headers
        expect(ids_in_response).to contain_exactly(unlocated.id, bare.id)
      end

      it 'combines with updated_since' do
        with_stock.update_columns(updated_at: 1.week.ago)
        get '/api/v1/products', params: { publishable: 'true', updated_since: 1.day.ago.iso8601 }, headers: headers
        expect(ids_in_response).to contain_exactly(on_preorder.id)
      end

      it 'ignores an empty value' do
        get '/api/v1/products', params: { publishable: '' }, headers: headers
        expect(ids_in_response).to contain_exactly(with_stock.id, on_preorder.id, unlocated.id, bare.id)
      end

      it 'rejects any other value' do
        get '/api/v1/products', params: { publishable: 'yes' }, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'keeps the filter on the next link' do
        stub_const('Api::V1::ProductsController::PER_PAGE', 1)
        get '/api/v1/products', params: { publishable: 'true' }, headers: headers
        expect(json['next']).to include('publishable=true')
      end
    end

    it 'paginates with an absolute next link until the last page' do
      stub_const('Api::V1::ProductsController::PER_PAGE', 2)
      3.times { product }

      get '/api/v1/products', headers: headers
      expect(json['items'].size).to eq(2)
      expect(json['next']).to start_with('http')

      get json['next'], headers: headers
      expect(json['items'].size).to eq(1)
      expect(json).not_to have_key('next')
    end

    it 'returns an empty page without next beyond the end' do
      product
      get '/api/v1/products', params: { page: 999 }, headers: headers
      expect(json).to eq('items' => [])
    end

    it 'filters by updated_since' do
      old = product
      old.update_columns(updated_at: 3.days.ago)
      fresh = product

      get '/api/v1/products', params: { updated_since: 1.day.ago.iso8601 }, headers: headers
      ids = json['items'].map { |item| item['id'] }
      expect(ids).to include(fresh.id)
      expect(ids).not_to include(old.id)
    end

    it 'rejects an invalid updated_since' do
      get '/api/v1/products', params: { updated_since: 'basura' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'requires products:read' do
      other = ApiKey.generate!(name: 'Fotos', scopes: ['photos:write'], created_by: admin).last
      get '/api/v1/products', headers: { 'Authorization' => "Bearer #{other}" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/products/:id' do
    it 'returns 404 for an unknown product' do
      get '/api/v1/products/0', headers: headers
      expect(response).to have_http_status(:not_found)
      expect(json).to eq('error' => 'Not found')
    end
  end

  describe 'GET /api/v1/products/exists' do
    it 'keeps answering exists for the legacy token' do
      admin.update_column(:api_token, SecureRandom.hex(20))
      record = product
      get '/api/v1/products/exists', params: { whatsapp_code: record.whatsapp_code },
                                     headers: { 'Authorization' => "Token #{admin.api_token}" }
      expect(json).to eq('exists' => true)
    end
  end
end
