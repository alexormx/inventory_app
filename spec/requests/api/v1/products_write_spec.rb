# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API v1 products (write)', type: :request do
  let(:admin) { create(:user, :admin) }

  def key(*scopes)
    ApiKey.generate!(name: 'KataFrame', scopes: scopes.presence || ApiKey::SCOPES, created_by: admin).last
  end

  def auth(token)
    { 'Authorization' => "Bearer #{token}" }
  end

  def json
    JSON.parse(response.body)
  end

  def photo(name = 'test1.png')
    fixture_file_upload(Rails.root.join('spec/fixtures/files', name), 'image/png')
  end

  def existing(**attrs)
    create(:product, skip_seed_inventory: true, status: 'draft', **attrs)
  end

  let(:fields) { { product_name: 'Nissan Skyline', brand: 'Tomica', category: 'diecast', selling_price: '199' } }

  describe 'POST /api/v1/products' do
    it 'creates from JSON and answers with the public representation' do
      post '/api/v1/products', params: { product: fields }.to_json,
                               headers: auth(key).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:created)
      expect(json['product_name']).to eq('Nissan Skyline')
      expect(json['id']).to be_present
      expect(json).not_to have_key('product_sku')
    end

    it 'creates from multipart with photos, as KataFrame sends it' do
      post '/api/v1/products', params: { product: fields.merge(product_images: [photo, photo('test2.png')]) },
                               headers: auth(key)
      expect(response).to have_http_status(:created)
      expect(json['image_urls'].size).to eq(2)
    end

    it 'ignores a product_sku sent with an API key' do
      post '/api/v1/products', params: { product: fields.merge(product_sku: 'X-SUPPLIER') }, headers: auth(key)
      expect(Product.find(json['id']).product_sku).to start_with('KF')
    end

    it 'requires photos:write to create with photos' do
      post '/api/v1/products', params: { product: fields.merge(product_images: [photo]) },
                               headers: auth(key('products:write'))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq('error' => 'Forbidden: missing scope photos:write')
    end

    it 'keeps the legacy create contract for the legacy token' do
      admin.update_column(:api_token, SecureRandom.hex(20))
      post '/api/v1/products',
           params: { product: fields.merge(product_sku: 'LEGACY-1', minimum_price: '100', maximum_discount: '0',
                                           product_images: [photo]) },
           headers: { 'Authorization' => "Token #{admin.api_token}" }
      expect(response).to have_http_status(:created)
      expect(json.keys).to match_array(%w[message id image_urls])
      expect(json['message']).to eq('Product created')
      expect(Product.find(json['id']).product_sku).to eq('LEGACY-1')
    end
  end

  describe 'PATCH /api/v1/products/:id' do
    it 'accepts a photos-only multipart request with just photos:write' do
      product = existing
      patch "/api/v1/products/#{product.id}", params: { product: { product_images: [photo('test2.png')] } },
                                              headers: auth(key('photos:write'))
      expect(response).to have_http_status(:ok)
      expect(json['image_urls'].size).to eq(3)
      expect(json['image_urls'].last).to include(product.reload.ordered_product_images.last.blob.signed_id)
    end

    it 'requires products:write to change fields' do
      product = existing
      patch "/api/v1/products/#{product.id}", params: { product: { selling_price: '250' } },
                                              headers: auth(key('photos:write'))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq('error' => 'Forbidden: missing scope products:write')
    end

    it 'answers 200 without changes for an empty body' do
      product = existing
      patch "/api/v1/products/#{product.id}", headers: auth(key)
      expect(response).to have_http_status(:ok)
    end

    it 'removes a custom attribute sent blank over multipart' do
      product = existing(custom_attributes: { 'series' => 'A', 'color' => 'rojo' })
      patch "/api/v1/products/#{product.id}", params: { product: { custom_attributes: { color: '' } } },
                                              headers: auth(key)
      expect(response).to have_http_status(:ok)
      expect(product.reload.custom_attributes).to eq('series' => 'A')
    end

    it 'refuses to publish an ineligible product' do
      product = existing
      patch "/api/v1/products/#{product.id}", params: { product: { status: 'active' } }, headers: auth(key)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to eq('errors' => [Api::ProductWriter::PUBLISH_ERROR])
    end

    it 'publishes a product with publishable stock' do
      product = existing
      Inventory.create!(product: product, purchase_cost: 10, status: :available,
                        inventory_location: create(:inventory_location))
      patch "/api/v1/products/#{product.id}", params: { product: { status: 'active' } }, headers: auth(key)
      expect(response).to have_http_status(:ok)
      expect(json['status']).to eq('active')
    end

    it 'ignores supplier identifiers sent with an API key' do
      product = existing(product_sku: 'ORIGINAL', supplier_product_code: 'SUP-1')
      patch "/api/v1/products/#{product.id}",
            params: { product: { product_sku: 'HACK', supplier_product_code: 'HACK', product_name: 'Nuevo' } },
            headers: auth(key)
      product.reload
      expect([product.product_sku, product.supplier_product_code, product.product_name]).to eq(%w[ORIGINAL SUP-1 Nuevo])
    end

    it 'returns 404 for an unknown product' do
      patch '/api/v1/products/0', params: { product: { product_name: 'x' } }, headers: auth(key)
      expect(response).to have_http_status(:not_found)
      expect(json).to eq('error' => 'Not found')
    end

    it 'returns 422 with errors on validation failure' do
      product = existing
      patch "/api/v1/products/#{product.id}", params: { product: { selling_price: '0' } }, headers: auth(key)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['errors']).to be_present
    end
  end
end
