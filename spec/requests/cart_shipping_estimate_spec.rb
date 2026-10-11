# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Envío estimado en el carrito', type: :request do
  before do
    ShippingMethod.delete_all
    create(:shipping_method, code: 'envio_estandar', base_cost: 60, active: true)
    create(:shipping_method, code: 'envio_express', base_cost: 180, active: true)
    product = create(:product, selling_price: 100, minimum_price: 100)
    post cart_items_path, params: { product_id: product.id }
  end

  it 'muestra el envío desde la tarifa activa más barata' do
    allow(Shipping::Calculator).to receive(:free_shipping?).and_return(false)
    get cart_path
    expect(response.body).to include('desde $60')
  end

  it 'muestra envío gratis cuando aplica' do
    allow(Shipping::Calculator).to receive(:free_shipping?).and_return(true)
    get cart_path
    expect(response.body).to include('¡Gratis!')
  end
end
