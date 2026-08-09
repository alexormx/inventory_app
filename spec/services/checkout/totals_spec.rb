# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Checkout::Totals' do
  let(:user) { create(:user) }
  let(:address) { create(:shipping_address, user: user) }
  let(:product) { create(:product, selling_price: 100.00) }
  let(:cart) do
    Cart.new(
      cart: {
        product.id.to_s => { 'brand_new' => 1 }
      }
    )
  end

  before do
    SiteSetting.delete_all
    create(:shipping_method, code: 'envio_estandar', base_cost: 99.00, active: true)
  end

  it 'calculates a decimal server-side total with added IVA enabled' do
    SiteSetting.set('tax_enabled', true, 'boolean')
    SiteSetting.set('tax_rate_percent', '16.00', 'string')

    totals = Checkout::Totals.new(
      cart: cart,
      shipping_method: 'envio_estandar',
      user: user,
      address: address
    ).call

    expect(totals.subtotal).to eq(100.to_d)
    expect(totals.tax_rate).to eq(16.to_d)
    expect(totals.tax_amount).to eq(16.to_d)
    expect(totals.shipping_amount).to eq(99.to_d)
    expect(totals.total).to eq(215.to_d)
  end

  it 'does not add tax when the current setting is disabled' do
    SiteSetting.set('tax_enabled', false, 'boolean')
    SiteSetting.set('tax_rate_percent', '16.00', 'string')

    totals = Checkout::Totals.new(
      cart: cart,
      shipping_method: 'envio_estandar',
      user: user,
      address: address
    ).call

    expect(totals.tax_rate).to eq(0.to_d)
    expect(totals.tax_amount).to eq(0.to_d)
    expect(totals.total).to eq(199.to_d)
  end

  it 'continues adding shipping to the total when the free-shipping promotion is disabled' do
    SiteSetting.set('tax_enabled', false, 'boolean')
    SiteSetting.set('free_shipping_enabled', false, 'boolean')

    totals = Checkout::Totals.new(
      cart: cart,
      shipping_method: 'envio_estandar',
      user: user,
      address: address
    ).call

    expect(totals.subtotal).to eq(100.to_d)
    expect(totals.shipping_amount).to eq(99.to_d)
    expect(totals.total).to eq(199.to_d)
  end
end
