# frozen_string_literal: true

require 'swagger_helper'

# Documentación OpenAPI de la API de productos (KataFrame). Regenerar el archivo
# con `bin/rails rswag:specs:swaggerize` al cambiar esta spec.
RSpec.describe 'API V1 Products', type: :request, rswag: true do
  let(:admin) { create(:user, :admin) }
  let(:token) { ApiKey.generate!(name: 'KataFrame', scopes: ApiKey::SCOPES, created_by: admin).last }
  let(:Authorization) { "Bearer #{token}" }

  def photo
    fixture_file_upload(Rails.root.join('spec/fixtures/files/test1.png'), 'image/png')
  end

  path '/api/v1/products' do
    get 'Listar productos' do
      tags 'Productos'
      description 'Todos los productos (borradores, inactivos y agotados incluidos), 100 por página en orden de id. ' \
                  'Seguir `next` hasta que no venga.'
      produces 'application/json'
      security [api_token: []]
      metadata[:operation][:'x-permisos'] = ['products:read']

      parameter name: :page, in: :query, type: :integer, required: false, description: 'Página (desde 1)'
      parameter name: :updated_since, in: :query, type: :string, format: 'date-time', required: false,
                description: 'Solo productos cambiados desde esta fecha ISO 8601'

      let(:page) { nil }
      let(:updated_since) { nil }

      response '200', 'una página de productos' do
        schema type: :object,
               properties: {
                 items: { type: :array, items: { '$ref' => '#/components/schemas/Product' } },
                 next: { type: :string, format: :uri, description: 'Siguiente página; falta en la última' }
               },
               required: ['items']
        before { create(:product, skip_seed_inventory: true) }
        run_test!
      end

      response '401', 'clave inválida o revocada' do
        let(:Authorization) { 'Bearer pk_invalida' }
        run_test!
      end

      response '403', 'la clave no tiene products:read' do
        let(:token) { ApiKey.generate!(name: 'Fotos', scopes: ['photos:write'], created_by: admin).last }
        schema '$ref' => '#/components/schemas/SingleError'
        run_test!
      end

      response '422', 'updated_since no es ISO 8601' do
        let(:updated_since) { 'ayer' }
        schema '$ref' => '#/components/schemas/Errors'
        run_test!
      end
    end

    post 'Crear producto' do
      tags 'Productos'
      description 'Crea un producto con SKU interno `KF…` generado. Precio mínimo = precio de venta. ' \
                  'Con fotos, enviar multipart (`product[...]`, `product[product_images][]`) y tener `photos:write`. ' \
                  "Todo o nada: si algo falla no se crea nada.\n\n" \
                  'El token del administrador conserva el contrato anterior (acepta `product_sku` y ' \
                  'responde `{message, id, image_urls}`).'
      consumes 'application/json', 'multipart/form-data'
      produces 'application/json'
      security [api_token: []]
      metadata[:operation][:'x-permisos'] = ['products:write', 'photos:write (si trae fotos)']

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { product: { '$ref' => '#/components/schemas/ProductInput' } },
        required: ['product']
      }

      let(:body) { { product: { product_name: 'Nissan Skyline', brand: 'Tomica', category: 'diecast', selling_price: 199 } } }

      response '201', 'producto creado' do
        schema '$ref' => '#/components/schemas/Product'
        run_test!
      end

      response '403', 'la clave no tiene products:write' do
        let(:token) { ApiKey.generate!(name: 'Lectura', scopes: ['products:read'], created_by: admin).last }
        schema '$ref' => '#/components/schemas/SingleError'
        run_test!
      end

      response '422', 'validación o no se puede publicar' do
        let(:body) { { product: { product_name: 'Sin precio', status: 'active' } } }
        schema '$ref' => '#/components/schemas/Errors'
        run_test!
      end
    end
  end

  path '/api/v1/products/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true

    let(:existing_product) { create(:product, skip_seed_inventory: true, status: 'draft') }
    let(:id) { existing_product.id }

    get 'Ver producto' do
      tags 'Productos'
      produces 'application/json'
      security [api_token: []]
      metadata[:operation][:'x-permisos'] = ['products:read']

      response '200', 'el producto' do
        schema '$ref' => '#/components/schemas/Product'
        run_test!
      end

      response '404', 'no existe' do
        let(:id) { 0 }
        schema '$ref' => '#/components/schemas/SingleError'
        run_test!
      end
    end

    patch 'Editar producto / agregar fotos' do
      tags 'Productos'
      description 'Solo cambia los campos enviados. Las fotos se agregan al final (la principal no cambia). ' \
                  'Una petición solo con fotos necesita únicamente `photos:write`. ' \
                  'Pasar a `status: active` publica con la misma regla que el admin.'
      consumes 'multipart/form-data', 'application/json'
      produces 'application/json'
      security [api_token: []]
      metadata[:operation][:'x-permisos'] = ['products:write (campos)', 'photos:write (fotos)']

      parameter name: :product, in: :formData, schema: {
        type: :object,
        properties: { product: { '$ref' => '#/components/schemas/ProductInput' } }
      }

      # rswag manda cada parámetro formData con su nombre: `product` => campos
      let(:product) { { product_name: 'Nissan Skyline R34', product_images: [photo] } }

      response '200', 'producto actualizado' do
        schema '$ref' => '#/components/schemas/Product'
        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body['product_name']).to eq('Nissan Skyline R34')
          expect(body['image_urls'].size).to eq(existing_product.product_images.count)
          expect(existing_product.product_images.count).to eq(3)
        end
      end

      response '422', 'no se puede publicar' do
        let(:product) { { status: 'active' } }
        schema '$ref' => '#/components/schemas/Errors'
        run_test!
      end
    end
  end

  path '/api/v1/products/exists' do
    get 'Verificar código' do
      tags 'Productos'
      description '¿Existe un producto con este código público (whatsapp_code)?'
      produces 'application/json'
      security [api_token: []]
      metadata[:operation][:'x-permisos'] = ['cualquier clave válida']

      parameter name: :whatsapp_code, in: :query, type: :string, required: true, example: 'AB12'

      response '200', 'resultado' do
        let(:whatsapp_code) { 'ZZ99' }
        schema type: :object, properties: { exists: { type: :boolean } }, required: ['exists']
        run_test!
      end
    end
  end
end
