# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Checkouts", type: :request do
  let!(:user) { create(:user) }
  let!(:product) { create(:product, selling_price: 10.0, minimum_price: 5.0) }
  let!(:address) { create(:shipping_address, user: user, default: true) }

  before do
    sign_in user
  end

  it "creates a sale order and clears the cart" do
    post cart_items_path, params: { product_id: product.id }
    
    # Completar el flujo de checkout para generar el token
    post checkout_step2_path, params: {
      selected_address_id: address.id,
      shipping_method: 'standard'
    }
    get checkout_step3_path
    checkout_token = session[:checkout_token]

    expect {
      post checkout_complete_path, params: {
        payment_method: 'efectivo',
        checkout_token: checkout_token,
        accept_pending: '1'
      }
    }.to change(SaleOrder, :count).by(1)

    expect(session[:cart]).to be_empty
    sale_order = SaleOrder.last
    expect(sale_order.sale_order_items.count).to eq(1)
    expect(sale_order.subtotal).to eq(10.0)
  end
end
