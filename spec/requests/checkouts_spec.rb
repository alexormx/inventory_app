require 'rails_helper'

RSpec.describe "Checkouts", type: :request do
  let!(:user) { create(:user) }
  let!(:product) { create(:product, selling_price: 10.0) }

  before do
    sign_in user
  end

  it "creates a sale order and clears the cart" do
    post cart_items_path, params: { product_id: product.id }

    expect {
      post checkout_path, params: { sale_order: { notes: 'test' } }
    }.to change(SaleOrder, :count).by(1)

    expect(session[:cart]).to be_empty
    sale_order = SaleOrder.last
    expect(sale_order.sale_order_items.count).to eq(1)
    expect(sale_order.subtotal).to eq(10.0)
  end
end