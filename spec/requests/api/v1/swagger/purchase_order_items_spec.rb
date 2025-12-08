# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Purchase Order Items', type: :request do
  let(:admin_user) { create(:user, role: 'admin', api_token: 'test_token') }
  let(:supplier) { create(:user, :supplier) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:purchase_order) { create(:purchase_order, user: supplier) }

  path '/api/v1/purchase_order_items' do
    post 'Create a purchase order item' do
      tags 'Purchase Order Items'
      description 'Creates a single line item for a purchase order'
      consumes 'application/json'
      produces 'application/json'
      security [api_token: []]

      let(:Authorization) { "Bearer #{admin_user.api_token}" }
      let(:purchase_order_item) do
        {
          purchase_order_item: {
            purchase_order_id: purchase_order.id,
            product_id: product.id,
            quantity: 10,
            unit_cost: 10.0
          }
        }
      end

      parameter name: :purchase_order_item, in: :body, schema: {
        type: :object,
        properties: {
          purchase_order_item: {
            type: :object,
            properties: {
              purchase_order_id: { type: :string, description: 'Purchase Order ID', example: 'PO-202511-001' },
              product_sku: { type: :string, description: 'Product SKU (alternative to product_id)', example: 'SKU-001' },
              product_id: { type: :integer, description: 'Product ID (alternative to product_sku)', example: 1 },
              quantity: { type: :integer, description: 'Quantity', example: 10 },
              unit_cost: { type: :number, format: :float, description: 'Unit cost', example: 50.0 },
              unit_compose_cost_in_mxn: { type: :number, format: :float, description: 'Composed unit cost in MXN', example: 55.0 }
            },
            required: ['purchase_order_id', 'quantity', 'unit_cost']
          }
        },
        required: ['purchase_order_item']
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
        let(:purchase_order_item) do
          {
            purchase_order_item: {
              purchase_order_id: purchase_order.id,
              product_id: nil,
              quantity: 10,
              unit_cost: 10.0
            }
          }
        end
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end
    end
  end

  path '/api/v1/purchase_order_items/batch' do
    post 'Bulk create purchase order items' do
      tags 'Purchase Order Items'
      description 'Creates multiple line items for a purchase order with automatic cost distribution'
      consumes 'application/json'
      produces 'application/json'
      security [api_token: []]

      let(:Authorization) { "Bearer #{admin_user.api_token}" }
      let(:batch_request) do
        {
          purchase_order_id: purchase_order.id,
          items: [{ product_id: product.id, quantity: 10, unit_cost: 10.0 }]
        }
      end

      parameter name: :batch_request, in: :body, schema: {
        type: :object,
        properties: {
          purchase_order_id: { type: :string, description: 'Purchase Order ID', example: 'PO-202511-001' },
          items: {
            type: :array,
            items: {
              type: :object,
              properties: {
                product_sku: { type: :string, description: 'Product SKU', example: 'SKU-001' },
                quantity: { type: :integer, description: 'Quantity', example: 10 },
                unit_cost: { type: :number, format: :float, description: 'Unit cost', example: 50.0 },
                unit_compose_cost_in_mxn: { type: :number, format: :float, description: 'Composed unit cost in MXN', example: 55.0 }
              },
              required: ['product_sku', 'quantity', 'unit_cost']
            }
          }
        },
        required: ['purchase_order_id', 'items']
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
        let(:batch_request) do
          {
            purchase_order_id: 'INVALID-PO-ID',
            items: [{ product_id: product.id, quantity: 10, unit_cost: 10.0 }]
          }
        end
        schema '$ref' => '#/components/schemas/Error'
        run_test!
      end
    end
  end
end
