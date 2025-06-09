require 'rails_helper'

RSpec.describe "Carts", type: :request do
  let!(:product) { create(:product) }

  it "shows products in cart" do
    post cart_items_path, params: { product_id: product.id }
    get cart_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include(product.product_name)
  end
end