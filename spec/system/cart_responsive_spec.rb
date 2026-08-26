# frozen_string_literal: true

require 'rails_helper'

Selenium::WebDriver.logger.level = :warn

# Each system example verifies a complete responsive interaction and its coupled accessibility state.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe 'Responsive shopping cart', :js, type: :system do
  include Warden::Test::Helpers

  let(:user) { create(:user, confirmed_at: Time.current) }
  let!(:long_name_product) do
    create(
      :product,
      product_name: 'Tomica Limited Vintage Neo Nissan Skyline Super Silhouette Edición Conmemorativa Especial',
      selling_price: 199.99
    )
  end
  let!(:preorder_product) do
    create(
      :product,
      skip_seed_inventory: true,
      product_name: 'Modelo de preventa con llegada pendiente',
      selling_price: 350,
      preorder_available: true
    )
  end
  let(:extra_products) do
    create_list(:product, 3).each_with_index do |product, index|
      product.update!(product_name: "Producto adicional para scroll #{index + 1}")
    end
  end

  before do
    driven_by :selenium_chrome_headless
    resize_to(1440, 1000)
    login_as(user, scope: :user)
  end

  after do
    Warden.test_reset!
  end

  def resize_to(width, height)
    page.current_window.resize_to(width, height)
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      requestAnimationFrame(() => requestAnimationFrame(done));
    JS
  end

  def add_cart_item(product, expected_count:, condition: 'brand_new')
    result = page.evaluate_async_script(<<~JS, product.id, condition)
      const [productId, condition, done] = arguments;
      const token = document.querySelector('meta[name="csrf-token"]')?.content;
      fetch('/cart_items', {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': token
        },
        body: JSON.stringify({ product_id: productId, condition: condition })
      }).then(async (response) => {
        const body = await response.text();
        let payload = null;
        try { payload = JSON.parse(body); } catch (_error) {}
        done({ status: response.status, body, totalItems: payload?.total_items });
      }).catch((error) => done({ status: 0, body: error.message }));
    JS

    expect(result.fetch('status')).to eq(200), result.fetch('body')
    expect(result.fetch('totalItems')).to eq(expected_count)
  end

  def setup_cart_items(*items)
    visit root_path
    accept_cookies_if_present
    items.each_with_index do |entry, index|
      product, condition = entry.is_a?(Array) ? entry : [entry, 'brand_new']
      add_cart_item(product, condition: condition, expected_count: index + 1)
    end
    visit root_path
    expect(page).to have_css('#cart-count', text: items.size.to_s, visible: :all)
  end

  def visit_cart_with(*items)
    setup_cart_items(*items)
    visit cart_path
    expect(page).to have_css('.cart-item-row', count: items.size)
  end

  def mobile_layout_metrics
    page.evaluate_script(<<~JS)
      (() => {
        const rows = [...document.querySelectorAll('.cart-item-row')];
        const first = rows[0];
        const name = first.querySelector('.cart-product-name');
        const summary = document.querySelector('.cart-summary-card');
        const list = document.querySelector('.cart-items-shell');
        const checkout = document.querySelector('.cart-summary-actions .btn-primary');
        const actions = document.querySelector('.cart-summary-actions');
        const quantity = first.querySelector('.cart-quantity');
        const remove = first.querySelector('.cart-remove');
        const targets = [...first.querySelectorAll('.cart-qty-button, .cart-qty-input, .cart-remove-button')];
        const rowRects = rows.map((row) => row.getBoundingClientRect());

        return {
          clientWidth: document.documentElement.clientWidth,
          scrollWidth: document.documentElement.scrollWidth,
          rowDisplay: getComputedStyle(first).display,
          rowRadius: parseFloat(getComputedStyle(first).borderRadius),
          rowsSeparated: rowRects.length < 2 || rowRects[1].top > rowRects[0].bottom,
          nameWrapped: name.getBoundingClientRect().height > parseFloat(getComputedStyle(name).fontSize) * 1.5,
          unitPriceVisible: getComputedStyle(first.querySelector('.cart-unit-price')).display !== 'none',
          lineTotalVisible: getComputedStyle(first.querySelector('.cart-line-total')).display !== 'none',
          minimumTargetWidth: Math.min(...targets.map((target) => target.getBoundingClientRect().width)),
          minimumTargetHeight: Math.min(...targets.map((target) => target.getBoundingClientRect().height)),
          removeSeparated: remove.getBoundingClientRect().top >= quantity.getBoundingClientRect().bottom,
          summaryAfterItems: summary.getBoundingClientRect().top >= list.getBoundingClientRect().bottom,
          summaryPosition: getComputedStyle(summary).position,
          checkoutWidth: checkout.getBoundingClientRect().width,
          actionsWidth: actions.getBoundingClientRect().width
        };
      })()
    JS
  end

  def cart_touch_target_metrics
    page.evaluate_script(<<~JS)
      (() => {
        const row = document.querySelector('.cart-item-row');
        const selectors = {
          decrease: '[data-action~="click->cart-item#decrease"]',
          quantity: '.cart-qty-input',
          increase: '[data-action~="click->cart-item#increase"]',
          remove: '.cart-remove-button',
          checkout: '.cart-summary-actions .btn-primary',
          continueShopping: '.cart-summary-actions .btn-outline-secondary'
        };
        return Object.fromEntries(Object.entries(selectors).map(([name, selector]) => {
          const element = selector.startsWith('.cart-summary') ? document.querySelector(selector) : row.querySelector(selector);
          const rect = element.getBoundingClientRect();
          return [name, { width: rect.width, height: rect.height }];
        }));
      })()
    JS
  end

  def open_mobile_preview(width, height)
    resize_to(width, height)
    hamburger = find('#hamburger', visible: true)
    navbar_open = page.evaluate_script("document.getElementById('navbar-scroll').classList.contains('is-open')")
    hamburger.click unless navbar_open
    hamburger.hover
    find('[data-nav-link="cart"]', visible: true).hover
    expect(page).to have_css('#cart-preview.show', visible: true)
  end

  def expect_preview_concealed_with_focus(focus_selector = '[data-nav-link="cart"]')
    # The old regression removed `.show` briefly, then focus restoration
    # reopened the preview on the next animation frame. Waiting for `hidden`
    # proves the complete 200 ms conceal cycle finished without reopening.
    expect(page).to have_css('#cart-preview[hidden]:not(.show)', visible: :all)
    expect(page).to have_no_css('.site-navbar.cart-preview-open')
    expect(page.evaluate_script("document.activeElement.matches(#{focus_selector.to_json})")).to be(true)
    expect(find('[data-nav-link="cart"]', visible: :all)['aria-expanded']).to eq('false')
  end

  def close_preview_from_focused_button
    close_button = find('[data-cart-preview-close]')
    page.execute_script('arguments[0].focus()', close_button)
    expect(page.evaluate_script("document.activeElement.matches('[data-cart-preview-close]')")).to be(true)
    close_button.click
    expect_preview_concealed_with_focus
  end

  def preview_metrics
    page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector('#cart-preview.show');
        const header = panel.querySelector('.cart-preview-header');
        const footer = panel.querySelector('.cart-preview-footer');
        const cta = panel.querySelector('.cart-preview-cta');
        const scroll = panel.querySelector('.cart-preview-scroll');
        const rect = (element) => {
          const value = element?.getBoundingClientRect();
          return value && { top: value.top, left: value.left, right: value.right, bottom: value.bottom, width: value.width, height: value.height };
        };
        const targetSelector = [
          '.cart-preview-close',
          '.cart-mini-qty-form button',
          '.cart-preview-remove',
          '.cart-preview-cta'
        ].join(', ');
        return {
          viewportWidth: window.innerWidth,
          viewportHeight: window.innerHeight,
          documentClientWidth: document.documentElement.clientWidth,
          documentScrollWidth: document.documentElement.scrollWidth,
          panel: rect(panel),
          header: rect(header),
          footer: rect(footer),
          cta: rect(cta),
          scroll: rect(scroll),
          scrollHeight: scroll?.scrollHeight || 0,
          scrollClientHeight: scroll?.clientHeight || 0,
          scrollTop: scroll?.scrollTop || 0,
          targets: [...panel.querySelectorAll(targetSelector)].map((element) => {
            const value = element.getBoundingClientRect();
            return { label: element.getAttribute('aria-label') || element.textContent.trim(), width: value.width, height: value.height };
          })
        };
      })()
    JS
  end

  def expect_preview_contained(metrics)
    panel = metrics.fetch('panel')
    expect(panel.fetch('top')).to be >= 7.5
    expect(panel.fetch('left')).to be >= 7.5
    expect(panel.fetch('right')).to be <= metrics.fetch('viewportWidth') - 7.5
    expect(panel.fetch('bottom')).to be <= metrics.fetch('viewportHeight') - 7.5
    expect(metrics.fetch('cta').fetch('bottom')).to be <= panel.fetch('bottom')
    expect(metrics.fetch('header').fetch('top')).to be >= panel.fetch('top')
    expect(metrics.fetch('footer').fetch('bottom')).to be <= panel.fetch('bottom')
    expect(metrics.fetch('documentScrollWidth')).to be <= metrics.fetch('documentClientWidth') + 1
  end

  def cart_status_text
    page.evaluate_script("document.getElementById('cart-status')?.textContent.trim()")
  end

  def choose_cart_confirmation(label)
    expect(page).to have_css('#global-confirm-modal.show[aria-hidden="false"]', visible: true)

    within('#global-confirm-modal.show[aria-hidden="false"]') do
      expect(page).to have_button(label, disabled: false)
      click_button label
    end
  end

  it 'presents separated, overflow-free cards at all required phone sizes' do
    visit_cart_with(long_name_product, preorder_product)

    [[575, 800], [390, 844], [375, 667]].each do |width, height|
      resize_to(width, height)
      expect(page).to have_css('.cart-item-row', count: 2)
      metrics = mobile_layout_metrics

      expect(metrics.fetch('scrollWidth')).to be <= metrics.fetch('clientWidth') + 1
      expect(metrics.fetch('rowDisplay')).to eq('grid')
      expect(metrics.fetch('rowRadius')).to be >= 12
      expect(metrics.fetch('rowsSeparated')).to be(true)
      expect(metrics.fetch('nameWrapped')).to be(true)
      expect(metrics.fetch('unitPriceVisible')).to be(true)
      expect(metrics.fetch('lineTotalVisible')).to be(true)
      expect(metrics.fetch('minimumTargetWidth')).to be >= 43.5
      expect(metrics.fetch('minimumTargetHeight')).to be >= 43.5
      expect(metrics.fetch('removeSeparated')).to be(true)
      expect(metrics.fetch('summaryAfterItems')).to be(true)
      expect(metrics.fetch('summaryPosition')).to eq('static')
      expect(metrics.fetch('checkoutWidth')).to be_within(1).of(metrics.fetch('actionsWidth'))
      expect(page).to have_text('Nuevo')
      expect(page).to have_text('Reserva · Preventa')
      expect(page).to have_text('Precio unitario')
      expect(page).to have_text('Total del producto')
    end
  end

  it 'keeps every main-cart interactive target at least 44px below lg' do
    visit_cart_with(long_name_product, preorder_product)

    [[768, 1024], [667, 375]].each do |width, height|
      resize_to(width, height)
      expect(page).to have_css('.cart-item-row', count: 2)

      cart_touch_target_metrics.each_value do |rect|
        expect(rect.fetch('width')).to be >= 43.5
        expect(rect.fetch('height')).to be >= 43.5
      end
      expect(page.evaluate_script('document.documentElement.scrollWidth')).to be <= page.evaluate_script('document.documentElement.clientWidth') + 1
    end
  end

  it 'preserves the desktop table, right summary and sticky behavior' do
    resize_to(1440, 1000)
    visit_cart_with(long_name_product, preorder_product)

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const table = document.querySelector('.cart-items-table');
        const row = document.querySelector('.cart-item-row');
        const summary = document.querySelector('.cart-summary-card');
        return {
          rowDisplay: getComputedStyle(row).display,
          headDisplay: getComputedStyle(table.tHead).display,
          unitPriceDisplay: getComputedStyle(row.querySelector('.cart-unit-price')).display,
          summaryPosition: getComputedStyle(summary).position,
          summaryToRight: summary.getBoundingClientRect().left > table.getBoundingClientRect().left,
          columnsOverlapVertically: summary.getBoundingClientRect().top < table.getBoundingClientRect().bottom
        };
      })()
    JS

    expect(metrics).to include(
      'rowDisplay' => 'table-row',
      'headDisplay' => 'table-header-group',
      'unitPriceDisplay' => 'table-cell',
      'summaryPosition' => 'sticky',
      'summaryToRight' => true,
      'columnsOverlapVertically' => true
    )
  end

  it 'preserves explicit and computed table semantics with one stable live region' do
    visit_cart_with(long_name_product, preorder_product)
    resize_to(575, 800)

    expect(page).to have_css('table.cart-items-table[role="table"]', count: 1)
    expect(page).to have_css('thead[role="rowgroup"]', count: 1, visible: :all)
    expect(page).to have_css('tbody[role="rowgroup"]', count: 1)
    expect(page).to have_css('tfoot[role="rowgroup"]', count: 1, visible: :all)
    expect(page).to have_css('tr.cart-item-row[role="row"]', count: 2)
    expect(page).to have_css('th[role="columnheader"]', count: 5, visible: :all)
    expect(page).to have_css('tr.cart-item-row th[role="rowheader"]', count: 2)
    expect(page).to have_css('tr.cart-item-row td[role="cell"]', count: 8)
    expect(page).to have_css('#cart-status[role="status"][aria-live="polite"][aria-atomic="true"]', count: 1, visible: :all)
    expect(page).to have_css('.cart-page [aria-live], .cart-page [role="status"]', count: 1, visible: :all)
    expect(page).to have_no_css('#cart-total[aria-live], #cart-item-count[aria-live], #summary-grand-total[aria-live], .cart-line-total-value[aria-live]', visible: :all)
    expect(page).to have_no_css('#cart-count[aria-live]', visible: :all)
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.cart-items-table thead')).display")).not_to eq('none')

    accessibility_tree = page.driver.browser.execute_cdp('Accessibility.getFullAXTree')
    computed_roles = accessibility_tree.fetch('nodes').filter_map do |node|
      node.dig('role', 'value') unless node['ignored']
    end
    expect(computed_roles).to include('table', 'rowgroup', 'row', 'columnheader', 'rowheader')
    expect(computed_roles & %w[cell gridcell]).not_to be_empty
  end

  it 'updates quantities, rejects invalid totals and restores focus through final removal' do
    resize_to(1440, 1000)
    visit_cart_with(long_name_product, preorder_product)
    quantity = find("#cart_item_#{long_name_product.id}_brand_new_quantity")
    quantity_id = quantity[:id]
    initial_total = find('#summary-grand-total').text

    within("#cart_item_#{long_name_product.id}_brand_new") do
      find('[data-action~="click->cart-item#increase"]').click
    end
    expect(page).to have_field(quantity_id, with: '2')
    expect(find('#cart-count', visible: :all)).to have_text('3')
    expect(find('#summary-grand-total').text).not_to eq(initial_total)
    expect(cart_status_text).to match(/\ACantidad actualizada\. Total del carrito: \$.+\.\z/)

    within("#cart_item_#{long_name_product.id}_brand_new") do
      find('[data-action~="click->cart-item#decrease"]').click
    end
    expect(page).to have_field(quantity_id, with: '1')

    quantity.fill_in(with: '3')
    quantity.send_keys(:tab)
    expect(page).to have_field(quantity_id, with: '3')
    expect(find('#cart-count', visible: :all)).to have_text('4')

    quantity.fill_in(with: '4')
    quantity.send_keys(:tab)
    expect(page).to have_css('.flash-message.alert-danger .btn-close[aria-label="Cerrar mensaje"]')
    expect(page).to have_css('.flash-message.alert-danger', text: 'Máximo 3 unidades.')
    expect(page).to have_field(quantity_id, with: '3')

    within("#cart_item_#{long_name_product.id}_brand_new") { find('.cart-remove-button').click }
    choose_cart_confirmation('Cancelar')
    expect(page).to have_css("#cart_item_#{long_name_product.id}_brand_new")

    within("#cart_item_#{long_name_product.id}_brand_new") { find('.cart-remove-button').click }
    choose_cart_confirmation('Eliminar producto')
    expect(page).to have_no_css("#cart_item_#{long_name_product.id}_brand_new")
    expect(page).to have_css("#cart_item_#{preorder_product.id}_brand_new_quantity:focus")
    expect(find('#cart-count', visible: :all)).to have_text('1')
    expect(cart_status_text).to match(/\AProducto eliminado\. Total del carrito: \$.+\.\z/)

    within("#cart_item_#{preorder_product.id}_brand_new") { find('.cart-remove-button').click }
    choose_cart_confirmation('Eliminar producto')
    expect(page).to have_css('#cart-empty-state', text: 'Tu carrito está vacío')
    expect(page).to have_css('#cart-empty-cta:focus')
    expect(find('#cart-count', visible: :all)).to have_text('0')
    expect(cart_status_text).to eq('Carrito vacío.')
  end

  it 'keeps a one-item mini-cart contained at 667x375' do
    setup_cart_items(long_name_product)

    open_mobile_preview(667, 375)
    expect(page).to have_css('#cart-preview .cart-preview-item', count: 1)
    expect_preview_contained(preview_metrics)
  end

  it 'keeps a two-item mini-cart contained with tablet touch targets' do
    setup_cart_items(long_name_product, preorder_product)

    open_mobile_preview(768, 1024)
    expect(page).to have_css('#cart-preview .cart-preview-item', count: 2)
    metrics = preview_metrics
    expect_preview_contained(metrics)
    metrics.fetch('targets').each do |target|
      expect(target.fetch('width')).to be >= 43.5
      expect(target.fetch('height')).to be >= 43.5
    end
  end

  it 'keeps five mini-cart items contained and scrolls only the list at 667x375' do
    setup_cart_items(long_name_product, preorder_product, *extra_products)

    open_mobile_preview(667, 375)
    expect(page).to have_css('#cart-preview .cart-preview-item', count: 5)
    five_item_metrics = preview_metrics
    expect_preview_contained(five_item_metrics)
    expect(five_item_metrics.fetch('scrollHeight')).to be > five_item_metrics.fetch('scrollClientHeight')
    five_item_metrics.fetch('targets').each do |target|
      expect(target.fetch('width')).to be >= 43.5
      expect(target.fetch('height')).to be >= 43.5
    end

    page.execute_script("document.querySelector('.cart-preview-scroll').scrollTop = document.querySelector('.cart-preview-scroll').scrollHeight")
    scrolled_metrics = preview_metrics
    expect(scrolled_metrics.fetch('scrollTop')).to be > 0
    expect(scrolled_metrics.fetch('header').fetch('top')).to be_within(1).of(five_item_metrics.fetch('header').fetch('top'))
    expect(scrolled_metrics.fetch('footer').fetch('bottom')).to be_within(1).of(five_item_metrics.fetch('footer').fetch('bottom'))
    expect_preview_contained(scrolled_metrics)
  end

  it 'restores focus after mobile X close without reopening and preserves later keyboard opening' do
    setup_cart_items(long_name_product)
    open_mobile_preview(390, 844)

    close_preview_from_focused_button

    page.driver.browser.action.send_keys(:tab).perform
    expect(page.evaluate_script("document.activeElement.matches('[data-nav-link=\"cart\"]')")).to be(false)
    page.driver.browser.action.key_down(:shift).send_keys(:tab).key_up(:shift).perform

    expect(page.evaluate_script("document.activeElement.matches('[data-nav-link=\"cart\"]')")).to be(true)
    expect(page).to have_css('#cart-preview.show', visible: true)

    close_preview_from_focused_button
  end

  it 'keeps repeated desktop X close cycles closed with focus restored' do
    setup_cart_items(long_name_product)
    resize_to(1440, 1000)
    cart_link = find('[data-nav-link="cart"]', visible: true)

    2.times do
      cart_link.hover
      expect(page).to have_css('#cart-preview.show', visible: true)
      close_preview_from_focused_button
    end
  end

  it 'uses one delegated close route after Turbo replacement, Escape and an outside click' do
    setup_cart_items(long_name_product)
    open_mobile_preview(667, 375)

    within('#cart-preview .cart-preview-item') { find('.cart-mini-increase').click }
    expect(page).to have_css('#cart-preview.show', visible: true)
    expect(page).to have_css('#cart-preview .cart-mini-qty-current', text: '2')
    expect(page).to have_css('.site-navbar.cart-preview-open')

    close_preview_from_focused_button

    find('[data-nav-link="cart"]', visible: true).hover
    expect(page).to have_css('#cart-preview.show', visible: true)
    close_button = find('[data-cart-preview-close]')
    page.execute_script('arguments[0].focus()', close_button)
    page.driver.browser.action.send_keys(:escape).perform
    expect_preview_concealed_with_focus('#hamburger')

    find('#hamburger', visible: true).click
    find('[data-nav-link="cart"]', visible: true).hover
    expect(page).to have_css('#cart-preview.show', visible: true)
    find('#hamburger', visible: true).click
    expect(page).to have_no_css('#cart-preview.show')
    expect(page).to have_no_css('.site-navbar.cart-preview-open')
  end

  it 'uses the selected collectible condition in the mini-cart and exposes mobile touch targets' do
    collectible = create(:product, product_name: 'Pieza Mint en tránsito')
    create(:inventory, product: collectible, status: :in_transit, item_condition: :mint, selling_price: 450)

    setup_cart_items(long_name_product, [collectible, 'mint'])
    resize_to(390, 844)
    find('#hamburger').click
    cart_link = find('[data-nav-link="cart"]', visible: true)
    cart_link.hover

    expect(page).to have_css('#cart-preview.show', visible: true)
    preview_paint = page.evaluate_script(<<~JS)
      (() => {
        const panel = document.querySelector('#cart-preview.show');
        const rect = panel.getBoundingClientRect();
        const x = Math.min(window.innerWidth - 1, Math.max(0, rect.left + (rect.width / 2)));
        const y = Math.min(window.innerHeight - 1, Math.max(0, rect.top + 24));
        const painted = document.elementFromPoint(x, y);
        const style = getComputedStyle(panel);
        return {
          bounds: { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom, width: rect.width, height: rect.height },
          positioning: { position: style.position, left: style.left, top: style.top, transform: style.transform },
          intersectsViewport: rect.right > 0 && rect.left < window.innerWidth && rect.bottom > 0 && rect.top < window.innerHeight,
          insideViewport: rect.left >= 0 && rect.right <= window.innerWidth + 1 && rect.top >= 0 && rect.bottom <= window.innerHeight + 1,
          painted: painted === panel || panel.contains(painted)
        };
      })()
    JS
    expect(preview_paint).to include(
      'intersectsViewport' => true,
      'insideViewport' => true,
      'painted' => true
    )
    within("#cart-preview #cart_item_#{collectible.id}_mint") do
      expect(page).to have_text('Mint')
      expect(page).to have_text('En tránsito')
      expect(page).to have_no_text('En stock')
    end
    expect(page).to have_link('Ver carrito')

    target_sizes = page.evaluate_script(<<~JS)
      [...document.querySelectorAll('#cart-preview .cart-preview-close, #cart-preview .cart-mini-qty-form button, #cart-preview .cart-preview-remove, #cart-preview .cart-preview-cta')]
        .map((target) => {
          const rect = target.getBoundingClientRect();
          return { width: rect.width, height: rect.height };
        })
    JS
    expect(target_sizes).not_to be_empty
    expect(target_sizes.map { |size| size.fetch('width') }.min).to be >= 43.5
    expect(target_sizes.map { |size| size.fetch('height') }.min).to be >= 43.5

    find('[data-cart-preview-close]').click
    expect(page).to have_no_css('#cart-preview.show')
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
