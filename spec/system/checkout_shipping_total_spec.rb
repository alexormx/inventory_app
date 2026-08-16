# frozen_string_literal: true

require 'rails_helper'

Selenium::WebDriver.logger.level = :warn

RSpec.describe 'Checkout shipping total', :js, :system_smoke, type: :system do
  include Warden::Test::Helpers

  let(:user) { create(:user, confirmed_at: Time.current) }
  let(:address) { create(:shipping_address, user: user, default: true) }
  let!(:product) { create(:product, selling_price: 100.00, minimum_price: 50.00) }
  let(:standard_shipping) do
    create(:shipping_method, name: 'Envío Estándar', code: 'standard', base_cost: 99.00, position: 1)
  end
  let(:express_shipping) do
    create(:shipping_method, name: 'Envío Exprés', code: 'express', base_cost: 149.00, position: 2)
  end
  let(:free_shipping) do
    create(:shipping_method, name: 'Envío Gratis', code: 'free', base_cost: 0, position: 3)
  end

  before do
    driven_by :selenium_chrome_headless
    SiteSetting.delete_all
    SiteSetting.set('tax_enabled', false, 'boolean')
    SiteSetting.set('free_shipping_enabled', false, 'boolean')
    address
    standard_shipping
    express_shipping
    free_shipping
    login_as(user, scope: :user)

    visit root_path
    click_button 'Aceptar' if page.has_button?('Aceptar', wait: 2)
    add_result = page.evaluate_async_script(<<~JS, product.id)
      const [productId, done] = arguments;
      const token = document.querySelector('meta[name="csrf-token"]')?.content;
      fetch('/cart_items', {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': token
        },
        body: JSON.stringify({ product_id: productId, condition: 'brand_new' })
      }).then(async (response) => done({ status: response.status, body: await response.text() }));
    JS
    raise "Could not prepare cart: #{add_result.fetch('body')}" unless add_result.fetch('status') == 200
  end

  after { Warden.test_reset! }

  it 'adds numeric shipping cost instead of concatenating its serialized value' do
    visit checkout_step2_path

    find('input[name="shipping_method"][value="express"]').click

    expect(page).to have_css('#checkout-grand-total', text: '$249.00')
  end

  it 'keeps the product total unchanged for zero-cost shipping' do
    visit checkout_step2_path

    find('input[name="shipping_method"][value="free"]').click

    expect(page).to have_css('#checkout-shipping-cost', text: 'Gratis')
    expect(page).to have_css('#checkout-grand-total', text: '$100.00')
  end
end
