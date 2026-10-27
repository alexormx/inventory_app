# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Checkout requires the customer name', type: :request do
  let(:user) { create(:user, name: nil) }
  let(:product) { create(:product, selling_price: 100.00) }
  let(:address) { create(:shipping_address, user: user, default: true) }
  let!(:shipping_method) { create(:shipping_method, :standard) }
  let!(:payment_method) { create(:payment_method, :transferencia_bancaria) }

  before do
    sign_in user
    post cart_items_path, params: { product_id: product.id, quantity: 1 }
  end

  it 'asks for the name on the first step' do
    get checkout_step1_path

    expect(response.body).to include('name="customer_name"')
  end

  it 'does not continue without a name' do
    post checkout_step1_path, params: { customer_name: '  ' }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.name).to be_blank
  end

  it 'saves the name and continues to shipping' do
    post checkout_step1_path, params: { customer_name: ' Ana López ' }

    expect(response).to redirect_to(checkout_step2_path)
    expect(user.reload.name).to eq('Ana López')
  end

  it 'sends a nameless customer back to the first step from any later step' do
    get checkout_step2_path

    expect(response).to redirect_to(checkout_step1_path)
  end

  it 'does not create the order for a nameless customer' do
    post checkout_step2_path, params: { selected_address_id: address.id, shipping_method: shipping_method.code }

    expect { post checkout_complete_path, params: { payment_method: payment_method.code, checkout_token: 'x' } }
      .not_to change(SaleOrder, :count)
    expect(response).to redirect_to(checkout_step1_path)
  end

  context 'when the customer already has a name' do
    let(:user) { create(:user, name: 'Ana López') }

    it 'does not ask for it again' do
      get checkout_step1_path

      expect(response.body).not_to include('name="customer_name"')
    end
  end
end
