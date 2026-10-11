# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Notas del checkout', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    product = create(:product, selling_price: 100, minimum_price: 100)
    post cart_items_path, params: { product_id: product.id }
  end

  it 'acepta notas largas sin romper la sesión y guarda 1000 caracteres en el carrito' do
    post checkout_step1_path, params: { notes: 'x' * 5000 }
    expect(response).to redirect_to(checkout_step2_path)
    expect(ShoppingCarts::ActiveCartResolver.find(user).checkout_notes.length).to eq(1000)
    expect(session.to_h.keys).not_to include('checkout_notes')
  end

  it 'el campo limita a 1000 caracteres' do
    get checkout_step1_path
    expect(response.body).to match(/<textarea[^>]*maxlength="1000"/)
  end
end
