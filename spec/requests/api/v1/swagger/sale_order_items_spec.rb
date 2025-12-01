# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Sale Order Items', type: :request do
  path '/api/v1/sale_order_items' do
    post 'Create a sale order item' do
      tags 'Sale Order Items'
      description 'Creates a single line item for a sale order and reserves inventory'
      consumes 'application/json'
      produces 'application/json'
      security [api_token: []]

      parameter name: :sale_order_item, in: :body, schema: {
        type: :object,
        properties: {
          sale_order_item: {
            type: :object,
            properties: {
              sale_order_id: { type: :string, description: 'Sale Order ID', example: 'SO-202511-001' },
              product_sku: { type: :string, description: 'Product SKU (alternative to product_id)', example: 'SKU-001' },
              product_id: {type: :integer, description: 'Product ID (alternative to product_sku)', example: 1 },
              quantity: { type: :integer, description: 'Quantity', example: 5 },
              unit_final_price: { type: :number, format: :float, description: 'Final unit price after discount', example: 95.0 }
            },
            required: ['sale_order_id', 'quantity', 'unit_final_price']
          }
        },
        required: ['sale_order_item']
      }

      response '201', 'item created' do
        schema type: :object,
               properties: {
                 status: { type: :string, example: 'ok' },
                 id: { type: :integer, example: 1 }
               }

        run_test!
      end

      response '422', 'invalid request' do
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end
    end
  end

  path '/api/v1/sale_order_items/batch' do
    post 'Bulk create sale order items' do
      tags 'Sale Order Items'
      description: 'Creates multiple line items for a sale order and reserves inventory for each'
      consumes 'application/json'
      produces 'application/json'
      security [api_token: []]

      parameter name: :batch_request, in: :body, schema: {
        type: :object,
        properties: {
          sale_order_id: { type: :string, description: 'Sale Order ID', example: 'SO-202511-001' },
          items: {
            type: :array,
            items: {
              type: :object,
              properties: {
                product_sku: { type: :string, description: 'Product SKU', example: 'SKU-001' },
                quantity: { type: :integer, description: 'Quantity', example: 5 },
                unit_final_price: { type: :number, format: :float, description: 'Final unit price', example: 95.0 }
              },
              required: ['product_sku', 'quantity', 'unit_final_price']
            }
          }
        },
        required: ['sale_order_id', 'items']
      }

      response '201', 'items created' do
        schema type: :object,
               properties: {
                 status: { type: :string, example: 'ok' },
                 created: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :integer, example: 1 },
                       product_sku: { type: :string, example: 'SKU-001' }
                     }
                   }
                 },
                 errors: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       product_sku: { type: :string, example: 'SKU-999' },
                       error: { type: :string, example: 'Product not found' }
                     }
                   }
                 }
               }

        run_test!
      end

      response '422', 'invalid request' do
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end
    end
  end
end
