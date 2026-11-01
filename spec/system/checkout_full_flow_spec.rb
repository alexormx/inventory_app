# frozen_string_literal: true

require 'rails_helper'

Selenium::WebDriver.logger.level = :warn

# Recorrido completo de compra en el navegador: carrito → envío → pago →
# gracias, más los detalles de interfaz que el dueño reportó (doble recuadro
# al elegir dirección/pago y mini carrito que aparecía solo).
RSpec.describe 'Checkout full flow', :js, type: :system do
  include Warden::Test::Helpers

  let(:user) { create(:user, confirmed_at: Time.current) }
  let!(:product) { create(:product, selling_price: 100.00, minimum_price: 50.00) }

  before do
    driven_by :selenium_chrome_headless
    SiteSetting.delete_all
    SiteSetting.set('tax_enabled', false, 'boolean')
    SiteSetting.set('free_shipping_enabled', false, 'boolean')
    create(:shipping_address, user: user, default: true, label: 'Casa')
    create(:shipping_address, user: user, default: false, label: 'Oficina')
    create(:shipping_method, name: 'Envío Estándar', code: 'standard', base_cost: 99.00, position: 1)
    create(:payment_method, :transferencia_bancaria, position: 1)
    create(:payment_method, name: 'Pago en efectivo', code: 'efectivo', position: 2)
    login_as(user, scope: :user)

    visit root_path
    click_button 'Aceptar' if page.has_button?('Aceptar', wait: 2)
    status = page.evaluate_async_script(<<~JS, product.id)
      const [productId, done] = arguments;
      const token = document.querySelector('meta[name="csrf-token"]')?.content;
      fetch('/cart_items', {
        method: 'POST',
        headers: { 'Accept': 'application/json', 'Content-Type': 'application/json', 'X-CSRF-Token': token },
        body: JSON.stringify({ product_id: productId, condition: 'brand_new' })
      }).then((response) => done(response.status));
    JS
    raise "Could not prepare cart (#{status})" unless status == 200
  end

  after { Warden.test_reset! }

  def outline_of(label_text)
    page.evaluate_script(<<~JS)
      (() => {
        const label = [...document.querySelectorAll('label')].find((l) => l.textContent.includes(#{label_text.to_json}));
        return getComputedStyle(label).outlineStyle;
      })()
    JS
  end

  it 'buys from step 1 to the thank-you page and registers the shipment' do
    visit checkout_step1_path
    click_button 'Continuar con envío →'

    find('label', text: 'Oficina').click
    expect(outline_of('Oficina')).to eq('none')
    click_button 'Continuar con el pago'

    find('label', text: 'Pago en efectivo').click
    expect(outline_of('Pago en efectivo')).to eq('none')
    click_button 'Finalizar compra'

    expect(page).to have_content('¡Gracias por tu compra!')
    order = user.sale_orders.last
    expect(order.order_shipping_address.source_shipping_address_id)
      .to eq(user.shipping_addresses.find_by(label: 'Oficina').id)
    expect(order.payments.last.payment_method).to eq('efectivo')
    expect(order.shipment).to have_attributes(carrier: 'Envío Estándar', shipping_cost: 99)
  end

  it 'keeps the keyboard focus ring on selectable cards' do
    visit checkout_step2_path
    find('input[name="selected_address_id"]:checked').send_keys(:arrow_right)

    expect(page.evaluate_script(
             "getComputedStyle(document.querySelector('input[name=selected_address_id]:checked').closest('label')).outlineStyle"
           )).to eq('solid')
  end

  describe 'mini cart preview' do
    let(:link) { find('.site-navbar a[data-nav-link="cart"]') }

    def preview_shown?
      page.evaluate_script("document.getElementById('cart-preview').classList.contains('show')")
    end

    before { visit catalog_path }

    it 'does not open when the pointer only passes over the cart link' do
      # Un solo trazo rápido, como al ir hacia "Favoritos" o "Mi cuenta".
      page.driver.browser.action(duration: 0).move_to(link.native).pause(duration: 0.05).move_by(0, 300).perform
      sleep 0.5

      expect(preview_shown?).to be(false)
    end

    it 'opens when the pointer rests on the cart link' do
      link.hover

      expect(page).to have_css('#cart-preview.show', wait: 2)
    end

    it 'does not open when the link regains focus without the keyboard' do
      # Tras un clic con el mouse (no teclado), el foco programático o el que
      # devuelve el navegador al volver a la pestaña no es :focus-visible.
      find('h1, h2, main', match: :first).click
      page.execute_script("document.querySelector('.site-navbar a[data-nav-link=\"cart\"]').focus()")
      sleep 0.5

      expect(preview_shown?).to be(false)
    end
  end
end
