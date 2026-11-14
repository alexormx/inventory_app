# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin quick_add: precio y errores con fotos', type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  def photo
    Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/test1.png'), 'image/png')
  end

  def quick_add(product_selling_price:, inventory_selling_price:)
    post admin_collectibles_quick_add_path, params: {
      use_existing_product: '0',
      product: { product_name: 'Komatsu WS-16', category: 'Autos a Escala', brand: 'Takara Tomy',
                 selling_price: product_selling_price },
      inventory: { item_condition: 'mib', purchase_cost: '150', selling_price: inventory_selling_price,
                   three_quarter_image: photo, piece_images: [photo] }
    }
  end

  it 'sin precio de referencia, el producto toma el precio de venta de la pieza' do
    expect { quick_add(product_selling_price: '', inventory_selling_price: '400') }
      .to change(Product, :count).by(1).and change(Inventory, :count).by(1)

    expect(Product.order(:id).last.selling_price).to eq(400)
    expect(response).to have_http_status(:redirect)
  end

  it 'si la validación falla con fotos adjuntas, vuelve a mostrar el formulario sin error 500' do
    expect { quick_add(product_selling_price: '', inventory_selling_price: '') }
      .not_to change(Product, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
