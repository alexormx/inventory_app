# frozen_string_literal: true

require 'rails_helper'
require 'rswag/specs'

RSpec.configure do |config|
  # Specify a root folder where Swagger JSON files are generated
  # NOTE: If you're using the rswag-api to serve API descriptions, you'll need
  # to ensure that it's configured, as per the Readme, to route requests to where
  # swagger/v1/swagger.json can be found
  config.openapi_root = Rails.root.join('swagger').to_s

  # Define one or more Swagger documents and provide global metadata for each one
  # When you run the 'rswag:specs:swaggerize' rake task, the complete Swagger will
  # be generated at the provided relative path under openapi_root
  # By default, the operations defined in spec files are added to the first
  # document below. You can override this behavior by adding a openapi_spec tag to the
  # the root example_group in your specs, e.g. describe '...', openapi_spec: 'v2/swagger.json'
  config.openapi_specs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'Inventory Management API V1',
        version: 'v1',
        description: 'API for managing inventory, products, orders, and more. This API provides programmatic  access to create and manage products, users, purchase orders, sale orders, and order line items.',
        contact: {
          name: 'API Support',
          email: 'support@inventoryapp.com'
        }
      },
      paths: {},
      servers: [
        {
          url: 'http://localhost:3000',
          description: 'Development server'
        },
        {
          url: 'https://your-production-domain.com',
          description: 'Production server'
        }
      ],
      components: {
        securitySchemes: {
          api_token: {
            type: :apiKey,
            name: 'Authorization',
            in: :header,
            description: 'API token for authentication. Format: "Bearer YOUR_API_TOKEN"'
          }
        },
        schemas: {
          Error: {
            type: :object,
            properties: {
              status: { type: :string, example: 'error' },
              message: { type: :string, example: 'Resource not found' },
              errors: {
                type: :array,
                items: { type: :string }
              }
            }
          },
          Product: {
            type: :object,
            properties: {
              id: { type: :integer, example: 1 },
              product_sku: { type: :string, example: 'SKU-001' },
              product_name: { type: :string, example: 'Product Name' },
              brand: { type: :string, example: 'Brand Name' },
              category: { type: :string, example: 'Category' },
              selling_price: { type: :number, format: :float, example: 99.99 },
              status: { type: :string, enum: ['draft', 'active', 'inactive'], example: 'active' }
            }
          },
          User: {
            type: :object,
            properties: {
              id: { type: :integer, example: 1 },
              email: { type: :string, format: :email, example: 'user@example.com' },
              name: { type: :string, example: 'John Doe' },
              role: { type: :string, enum: ['customer', 'admin'], example: 'customer' }
            }
          },
          PurchaseOrder: {
            type: :object,
            properties: {
              id: { type: :string, example: 'PO-202511-001' },
              order_date: { type: :string, format: :date, example: '2025-11-30' },
              total_order_cost: { type: :number, format: :float, example: 1500.50 },
              status: { type: :string, example: 'Pending' }
            }
          },
          SaleOrder: {
            type: :object,
            properties: {
              id: { type: :string, example: 'SO-202511-001' },
              order_date: { type: :string, format: :date, example: '2025-11-30' },
              total_order_value: { type: :number, format: :float, example: 2500.75 },
              status: { type: :string, example: 'Pending' }
            }
          }
        }
      }
    }
  }

  # Specify the format of the output Swagger file when running 'rswag:specs:swaggerize'.
  # The openapi_specs configuration option has the filename including format in
  # the key, this may want to be changed to avoid putting yaml in json files.
  # Defaults to json. Accepts ':json' and ':yaml'.
  config.openapi_format = :yaml
end
