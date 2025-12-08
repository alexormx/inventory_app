# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Sale Order Items', type: :request, rswag: true do
  let(:admin_user) { create(:user, role: 'admin', api_token: 'test_token_soi') }
  let(:customer) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:purchase_order) { create(:purchase_order) }
  let(:sale_order) { create(:sale_order, user: customer) }

  path '/api/v1/sale_order_items' do
    post 'Create a sale order item' do
      tags 'Sale Order Items'
      description 'Creates a single line item for a sale order and reserves inventory'
      consumes 'application/json'
      produces 'application/json'
      security [api_token: []]

      let(:Authorization) { "Bearer #{admin_user.api_token}" }
      let(:sale_order_item) do
        # Create inventory before the API call
        create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: 10, unit_cost: 50.0)
        {
          sale_order_item: {
            sale_order_id: sale_order.id,
            product_id: product.id,
            quantity: 5,
            unit_final_price: 95.0
          }
        }
      end

      parameter name: :sale_order_item, in: :body, schema: {
        type: :object,
        properties: {
          sale_order_item: {
            type: :object,
            properties: {
              sale_order_id: { type: :string, description: 'Sale Order ID', example: 'SO-202511-001' },
              product_sku: { type: :string, description: 'Product SKU (alternative to product_id)', example: 'SKU-001' },
              product_id: { type: :integer, description: 'Product ID (alternative to product_sku)', example: 1 },
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

        # Ejecutar con limpieza transaccional controlada por metadata :rswag
        run_test!
      end

      response '422', 'invalid request' do
        let(:sale_order_item) do
          {
            sale_order_item: {
              sale_order_id: sale_order.id,
              product_id: nil,
              quantity: 5,
              unit_final_price: 95.0
            }
          }
        end
        schema '$ref' => '#/components/schemas/Error'
        # Ejecutar con limpieza transaccional controlada por metadata :rswag
        run_test!
      end
    end
  end

  path '/api/v1/sale_order_items/batch' do
    post 'Bulk create sale order items' do
      tags 'Sale Order Items'
      description 'Creates multiple line items for a sale order and reserves inventory for each'
      consumes 'application/json'
      produces 'application/json'
      security [api_token: []]

      let(:Authorization) { "Bearer #{admin_user.api_token}" }
      let(:batch_request) do
        create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: 10, unit_cost: 50.0)
        {
          sale_order_id: sale_order.id,
          items: [{ product_id: product.id, quantity: 5, unit_final_price: 95.0 }]
        }
      end

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
                   items: { type: :integer }
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

        # Ejecutar con limpieza transaccional controlada por metadata :rswag
        run_test!
      end

      response '422', 'invalid request' do
        let(:batch_request) do
          {
            sale_order_id: 'INVALID-SO-ID',
            items: [{ product_id: 999999, quantity: 5, unit_final_price: 95.0 }]
          }
        end
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end
    end
  end
end
