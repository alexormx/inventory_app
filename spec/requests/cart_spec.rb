require 'rails_helper'

RSpec.describe "Carts", type: :request do
  let!(:product) { create(:product) }

  it "shows products in cart" do
    post cart_items_path, params: { product_id: product.id }
    get cart_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include(product.product_name)
  end

  it 'moves the unit price into the product cell on narrow screens' do
    post cart_items_path, params: { product_id: product.id }
    get cart_path

    expect(response.body).to include('cart-unit-price d-none d-sm-table-cell')
    expect(response.body).to include('cart-mobile-unit-price d-sm-none')
    expect(response.body).to include('cart-line-total d-none d-sm-table-cell')
    expect(response.body).to include('cart-mobile-line-total d-sm-none')
    expect(response.body).to include('cart-remove d-none d-sm-table-cell')
  end
end
