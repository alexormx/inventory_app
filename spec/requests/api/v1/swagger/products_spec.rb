# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Products', type: :request do
  path '/api/v1/products' do
    post 'Create a product' do
      tags 'Products'
      description 'Creates a new product in the inventory system'
      consumes 'application/json'
      produces 'application/json'
      security [api_token: []]

      parameter name: :product, in: :body, schema: {
        type: :object,
        properties: {
          product: {
            type: :object,
            properties: {
              product_sku: { type: :string, description: 'Unique SKU identifier', example: 'SKU-001' },
              product_name: { type: :string, description: 'Product name', example: 'Test Product' },
              brand: { type: :string, description: 'Brand name', example: 'Brand Name' },
              category: { type: :string, description: 'Category', example: 'Electronics' },
              selling_price: { type: :number, format: :float, description: 'Selling price', example: 99.99 },
              maximum_discount: { type: :number, format: :float, description: 'Maximum discount allowed', example: 10.0 },
              minimum_price: { type: :number, format: :float, description: 'Minimum selling price', example: 85.0 },
              barcode: { type: :string, description: 'Barcode', example: '1234567890' },
              status: { type: :string,  description: 'Product status', enum: ['draft', 'active', 'inactive'], example: 'active' }
            },
            required: ['product_sku', 'product_name', 'brand', 'category', 'selling_price', 'maximum_discount', 'minimum_price']
          }
        },
        required: ['product']
      }

      response '201', 'product created' do
        schema type: :object,
               properties: {
                 status: { type: :string, example: 'ok' },
                 id: { type: :integer, example: 1 },
                 message: { type: :string, example: 'Product created successfully' }
               }

        run_test!
      end

      response '422', 'invalid request' do
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end
    end
  end

  path '/api/v1/products/exists' do
    get 'Check if product exists' do
      tags 'Products'
      description 'Check if a product exists by SKU'
      produces 'application/json'
      security [api_token: []]

      parameter name: :product_sku, in: :query, type: :string, required: true, description: 'Product SKU to check', example: 'SKU-001'

      response '200', 'product exists' do
        schema type: :object,
               properties: {
                 exists: { type: :boolean, example: true },
                 product_id: { type: :integer, example: 1 }
               }

        run_test!
      end

      response '404', 'product not found' do
        schema type: :object,
               properties: {
                 exists: { type: :boolean, example: false }
               }
        run_test!
      end
    end
  end
end
