# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Products', type: :request do
  let(:admin_user) { create(:user, role: 'admin', api_token: 'test_token') }
  let(:Authorization) { "Bearer #{admin_user.api_token}" }

  path '/api/v1/products' do
    post 'Create a product' do
      tags 'Products'
      description 'Creates a new product in the inventory system'
      consumes 'application/json'
      produces 'application/json'
      security [api_token: []]

      let(:product) do
        {
          product: {
            product_sku: "SKU-TEST-#{SecureRandom.hex(4)}",
            product_name: 'Test Product',
            brand: 'Test Brand',
            category: 'diecast',
            selling_price: 100.0,
            maximum_discount: 10.0,
            minimum_price: 85.0
          }
        }
      end

      parameter name: :product, in: :body, schema: {
        type: :object,
        properties: {
          product: {
            type: :object,
            properties: {
              product_sku: { type: :string, description: 'Unique SKU identifier', example: 'SKU-001' },
              product_name: { type: :string, description: 'Product name', example: 'Test Product' },
              brand: { type: :string, description: 'Brand name', example: 'Brand Name' },
              category: { type: :string, description: 'Category', example: 'diecast' },
              selling_price: { type: :number, format: :float, description: 'Selling price', example: 99.99 },
              maximum_discount: { type: :number, format: :float, description: 'Maximum discount allowed', example: 10.0 },
              minimum_price: { type: :number, format: :float, description: 'Minimum selling price', example: 85.0 },
              barcode: { type: :string, description: 'Barcode', example: '1234567890' },
              status: { type: :string, description: 'Product status', enum: ['draft', 'active', 'inactive'], example: 'active' }
            },
            required: ['product_sku', 'product_name', 'brand', 'category', 'selling_price', 'maximum_discount', 'minimum_price']
          }
        },
        required: ['product']
      }

      response '201', 'product created' do
        schema type: :object,
               properties: {
                 message: { type: :string, example: 'Product created' },
                 id: { type: :integer, example: 1 },
                 image_urls: { type: :array, items: { type: :string } }
               }

        run_test!
      end

      response '422', 'invalid request' do
        let(:product) do
          {
            product: {
              product_sku: nil,
              product_name: nil,
              selling_price: 100.0
            }
          }
        end
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end
    end
  end

  path '/api/v1/products/exists' do
    get 'Check if product exists' do
      tags 'Products'
      description 'Check if a product exists by whatsapp_code'
      produces 'application/json'
      security [api_token: []]

      parameter name: :whatsapp_code, in: :query, type: :string, required: true, description: 'Product whatsapp code to check', example: 'WGT001'

      response '200', 'product exists' do
        let!(:existing_product) { create(:product, whatsapp_code: 'WGT-EXISTS-001') }
        let(:whatsapp_code) { 'WGT-EXISTS-001' }

        schema type: :object,
               properties: {
                 exists: { type: :boolean, example: true }
               }

        run_test!
      end

      response '200', 'product not found' do
        let(:whatsapp_code) { 'WGT-NOT-FOUND-999' }

        schema type: :object,
               properties: {
                 exists: { type: :boolean, example: false }
               }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['exists']).to eq(false)
        end
      end
    end
  end
end
