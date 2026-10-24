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
        title: 'API del inventario (Pasatiempos)',
        version: 'v1',
        description: <<~MD
          API REST para integraciones como KataFrame.

          **Autenticación:** encabezado `Authorization: Bearer <clave>`. Las claves (`pk_…`) se crean en
          Admin › Configuración › Claves de API y llevan permisos: `products:read`, `products:write`,
          `photos:write`. El permiso que pide cada operación está en `x-permisos`.

          Las operaciones marcadas «Solo token de administrador» (órdenes, pagos, usuarios) responden
          `403` a cualquier clave; solo las acepta el token personal del administrador.

          **Errores:** `401` clave inválida o revocada · `403` falta un permiso · `404` no existe ·
          `422` validación (`{"errors": [...]}`).
        MD
      },
      paths: {},
      servers: [
        {
          url: 'https://pasatiempos.com.mx',
          description: 'Producción'
        },
        {
          url: 'http://localhost:3000',
          description: 'Desarrollo'
        }
      ],
      components: {
        securitySchemes: {
          api_token: {
            type: :http,
            scheme: :bearer,
            description: 'Clave de API (`pk_…`) o token del administrador'
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
          Errors: {
            type: :object,
            properties: { errors: { type: :array, items: { type: :string } } },
            required: ['errors']
          },
          SingleError: {
            type: :object,
            properties: { error: { type: :string, example: 'Not found' } },
            required: ['error']
          },
          # Lo que devuelve Api::V1::ProductSerializer: sin SKU ni datos de proveedor
          Product: {
            type: :object,
            properties: {
              id: { type: :integer, example: 1532 },
              code: { type: :string, nullable: true, description: 'Código público (whatsapp_code)', example: 'AB12' },
              product_name: { type: :string, example: 'Nissan Skyline GT-R' },
              brand: { type: :string, example: 'Tomica' },
              category: { type: :string, example: 'diecast' },
              series: { type: :string, nullable: true },
              scale: { type: :string, nullable: true, example: '1:64' },
              selling_price: { type: :string, description: 'Decimal como texto', example: '199.0' },
              description: { type: :string, nullable: true },
              status: { type: :string, enum: %w[draft active inactive], example: 'active' },
              barcode: { type: :string, nullable: true },
              launch_date: { type: :string, format: :date, nullable: true },
              stock_available: { type: :integer, description: 'Piezas que un cliente puede comprar ahora', example: 3 },
              publishable: { type: :boolean, description: 'Cumple la regla del admin para publicar: stock vendible, preventa o sobre pedido' },
              inventory: {
                type: :object,
                description: 'Piezas por estatus. `total` = todas menos sold, pre_sold, lost y scrap',
                properties: {
                  total: { type: :integer, example: 5 },
                  available: { type: :integer, description: 'Disponibles (con o sin ubicación)' },
                  reserved: { type: :integer, description: 'Apartadas para un pedido' },
                  in_transit: { type: :integer, description: 'En camino (compradas, sin llegar)' },
                  sold: { type: :integer, description: 'Vendidas' },
                  damaged: { type: :integer, description: 'Dañadas' },
                  lost: { type: :integer, description: 'Perdidas' },
                  returned: { type: :integer, description: 'Devueltas' },
                  scrap: { type: :integer, description: 'Merma' },
                  pre_reserved: { type: :integer, description: 'Pre apartadas (preventa)' },
                  pre_sold: { type: :integer, description: 'Pre vendidas (preventa)' },
                  marketing: { type: :integer, description: 'Para marketing' }
                },
                required: %w[total available reserved in_transit sold damaged lost returned scrap pre_reserved pre_sold marketing]
              },
              badge: { type: :string, nullable: true, example: 'Nuevo en catálogo',
                       description: 'Insignia de la tienda: Nuevo en catálogo, De vuelta en catálogo o Recién resurtido' },
              tags: { type: :array, items: { type: :string }, description: 'Etiquetas (palabras clave SEO)',
                      example: %w[tomica skyline] },
              length_cm: { type: :string, nullable: true },
              width_cm: { type: :string, nullable: true },
              height_cm: { type: :string, nullable: true },
              weight_gr: { type: :string, nullable: true },
              custom_attributes: { type: :object, additionalProperties: true },
              image_urls: { type: :array, items: { type: :string, format: :uri },
                            description: 'Fotos originales; la principal primero' },
              updated_at: { type: :string, format: 'date-time' }
            },
            required: %w[id product_name status selling_price stock_available image_urls updated_at]
          },
          ProductInput: {
            type: :object,
            description: 'Solo cambia lo que se manda. `status` o `code` vacíos se ignoran.',
            properties: {
              product_name: { type: :string },
              brand: { type: :string },
              category: { type: :string },
              series: { type: :string },
              scale: { type: :string },
              selling_price: { type: :number },
              description: { type: :string },
              barcode: { type: :string },
              launch_date: { type: :string, format: :date },
              status: { type: :string, enum: %w[draft active inactive],
                        description: '`active` publica: requiere existencias publicables, preventa o backorder (si no, 422)' },
              code: { type: :string, description: 'Sinónimo de whatsapp_code' },
              length_cm: { type: :number },
              width_cm: { type: :number },
              height_cm: { type: :number },
              weight_gr: { type: :number },
              custom_attributes: { type: :object, additionalProperties: true,
                                   description: 'Se combina con lo existente; una llave vacía se borra' },
              product_images: { type: :array, items: { type: :string, format: :binary },
                                description: 'Solo multipart (`product[product_images][]`): se agregan al final. ' \
                                             'Máx. 10 por petición, 15 MB c/u, JPG/PNG/WebP' }
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
