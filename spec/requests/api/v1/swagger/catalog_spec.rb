# frozen_string_literal: true

require 'swagger_helper'

# Sin `rswag: true`: el catálogo responde en stream (otro hilo) y necesita ver
# los datos de la transacción normal de la prueba.
RSpec.describe 'API V1 Catalog', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:Authorization) { "Bearer #{ApiKey.generate!(name: 'PDF', scopes: ['products:read'], created_by: admin).last}" }

  path '/api/v1/catalog' do
    get 'Catálogo para PDF' do
      tags 'Catálogo'
      description 'Productos ofertables con ubicación confirmada, en stream, para el generador de catálogos en PDF. ' \
                  '`image_url` es la foto principal reducida a 600×600.'
      produces 'application/json'
      security [api_token: []]
      metadata[:operation][:'x-permisos'] = ['products:read']

      response '200', 'ítems del catálogo' do
        schema type: :object,
               properties: {
                 items: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       code: { type: :string }, name: { type: :string }, brand: { type: :string },
                       series: { type: :string }, scale: { type: :string, nullable: true },
                       price: { type: :string }, event: { type: :string, nullable: true },
                       event_label: { type: :string, nullable: true },
                       launch_date: { type: :string, format: 'date-time', nullable: true },
                       product_url: { type: :string, format: :uri }, unique_piece: { type: :boolean },
                       image_url: { type: :string, format: :uri, nullable: true }
                     }
                   }
                 }
               },
               required: ['items']
        run_test!
      end
    end
  end
end
