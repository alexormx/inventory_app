# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Product page "Detalles del producto" labels', type: :request do
  it 'uses the category template label and sentence case for unknown keys' do
    create(:category_attribute_template, category: 'diecast',
                                         attributes_schema: [{ 'key' => 'suspension', 'label' => 'Suspensión', 'type' => 'string' }])
    product = create(:product, category: 'diecast',
                               custom_attributes: { 'suspension' => 'Funcional', 'fecha_de_lanzamiento' => '2026-10' })

    get product_path(product)

    detalles = response.body[/id="detalles".*?<\/div>\s*<\/div>\s*<\/div>/m]
    expect(detalles).to include('Suspensión')
    expect(detalles).to include('Fecha de lanzamiento')
    expect(detalles).not_to include('text-capitalize')
  end
end
