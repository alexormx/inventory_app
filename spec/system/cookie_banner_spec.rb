# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Cookie banner', :js, type: :system do
  before do
    driven_by :selenium_chrome_headless
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    page.execute_script('localStorage.clear(); sessionStorage.clear();')
    visit root_path
  end

  it 'is visible before the visitor decides' do
    expect(page).to have_css('#cookie-banner', visible: true)
  end

  it 'hides after acceptance' do
    click_button 'Aceptar'

    expect(page).to have_no_css('#cookie-banner', visible: :all)
  end

  it 'stays hidden after acceptance and reload' do
    click_button 'Aceptar'
    refresh

    expect(page).to have_no_css('#cookie-banner', visible: :all)
  end

  # El botón flotante de WhatsApp se superponía a "Aceptar" y Chrome entregaba el
  # clic al botón flotante (ElementClickInterceptedError). Se usa un clic nativo a
  # propósito: forzarlo con JavaScript volvería a ocultar la regresión.
  context 'with the floating WhatsApp button on a narrow viewport' do
    let(:original_size) { page.driver.browser.manage.window.size }

    before do
      original_size
      page.driver.browser.manage.window.resize_to(1000, 800)
    end

    after do
      page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
    end

    def control_rects
      page.evaluate_script(<<~JS)
        (function () {
          var accept = document.querySelector('#accept-cookies');
          var whatsapp = document.querySelector('.whatsapp-float-button');
          if (!accept || !whatsapp) { return null; }
          var a = accept.getBoundingClientRect();
          var w = whatsapp.getBoundingClientRect();
          return {
            overlap_x: Math.min(a.right, w.right) - Math.max(a.left, w.left),
            overlap_y: Math.min(a.bottom, w.bottom) - Math.max(a.top, w.top)
          };
        })();
      JS
    end

    it 'keeps the accept button clear of the floating button and accepts on a native click' do
      expect(page).to have_css('#cookie-banner', visible: true)
      expect(page).to have_css('.whatsapp-float-button', visible: true)

      rects = control_rects
      expect(rects).not_to be_nil
      # Rectángulos disjuntos: basta con que no se solapen en un eje.
      expect([rects['overlap_x'], rects['overlap_y']].min).to be <= 0

      click_button 'Aceptar'

      expect(page).to have_no_css('#cookie-banner', visible: :all)
    end
  end
end
