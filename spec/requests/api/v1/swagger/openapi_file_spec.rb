# frozen_string_literal: true

require 'rails_helper'

# /api-docs y la guía del admin leen swagger/v1/swagger.yaml del repo: se
# regenera con `bin/rails rswag:specs:swaggerize` y se versiona.
RSpec.describe 'OpenAPI file' do
  let(:doc) { YAML.safe_load_file(Rails.root.join('swagger/v1/swagger.yaml')) }

  it 'documents the product endpoints KataFrame uses' do
    expect(doc['paths'].keys).to include('/api/v1/products', '/api/v1/products/{id}', '/api/v1/catalog')
    expect(doc['paths']['/api/v1/products/{id}'].keys).to include('get', 'patch')
  end

  it 'states the permission of every operation an API key can call' do
    scopes = doc['paths'].values_at('/api/v1/products', '/api/v1/products/{id}')
                         .flat_map { |path| path.slice('get', 'post', 'patch').values.map { |op| op['x-permisos'] } }
    expect(scopes).to all(be_present)
  end

  it 'never documents supplier identifiers in the product representation' do
    expect(doc.dig('components', 'schemas', 'Product', 'properties').keys)
      .not_to include('product_sku', 'supplier_product_code')
  end
end
