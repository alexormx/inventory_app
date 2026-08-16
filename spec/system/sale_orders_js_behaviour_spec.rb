# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sale Order JS behaviour', :system_smoke, type: :system, js: true do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let!(:customer) { create(:user, name: 'Cliente de prueba') }
  let!(:product) { create(:product, product_name: 'Carro RC', product_sku: 'RC-001', selling_price: 100.0, weight_gr: 250, length_cm: 10, width_cm: 5, height_cm: 4) }

  before do
    login_as(admin, scope: :user)
  end

  def select_product(product)
    fill_in 'product-search', with: product.product_name
    within '#product-search-results' do
      expect(page).to have_css('button', text: product.product_name)
      find('button', text: product.product_name).click
    end
  end

  it 'adds a single row per product selection and updates totals live' do
    visit new_admin_sale_order_path

    expect(page).to have_css('#order-items-table')

    # Reproduce repeated Turbo lifecycle events without replacing the current DOM.
    page.execute_script(<<~JS)
      document.dispatchEvent(new Event('turbo:load'));
      document.dispatchEvent(new Event('turbo:load'));
      document.dispatchEvent(new Event('turbo:before-cache'));
      document.dispatchEvent(new Event('turbo:load'));
    JS

    # Use the real Stimulus search UI and select the product exactly once.
    select_product(product)

    expect(page).to have_css('#order-items-table tbody tr.item-row', count: 1)

    # Cambiar cantidad y precio unitario
    find('#order-items-table tbody tr.item-row input.item-qty').fill_in(with: '2')
    find('#order-items-table tbody tr.item-row input.item-unit-cost').fill_in(with: '150')
    # Aplicar descuento unitario
    find('#order-items-table tbody tr.item-row input.item-unit-discount').fill_in(with: '10')

    # Verificar subtotal y totales en displays (pueden tardar por eventos input)
    expect(page).to have_css('#display-subtotal', text: '$280.00') # 2 * (150 - 10)

    # Cambiar descuento general e impuesto (el impuesto dispara el recálculo existente)
    find('#sale_order_discount').fill_in(with: '20')
    find('#sale_order_tax_rate').fill_in(with: '16')

    # Cálculo: subtotal=280, IVA=44.8, total=304.8
    expect(page).to have_css('#display-total-tax', text: '$44.80')
    expect(page).to have_css('#display-total', text: '$304.80')

    # Sidebar
    expect(page).to have_css('#summary-items-count', text: '1')
    expect(page).to have_css('#summary-total-qty', text: '2')
    expect(page).to have_css('#summary-subtotal', text: '$280.00')
    expect(page).to have_css('#summary-tax', text: '$44.80')
    expect(page).to have_css('#summary-total', text: '$304.80')

    find('#order-items-table tbody tr.item-row .remove-item').click
    expect(page).to have_no_css('#order-items-table tbody tr.item-row')
    expect(page).to have_css('#summary-items-count', text: '0')
  end

  it 'submits the sale order with the selected product' do
    visit new_admin_sale_order_path

    select_product(product)
    page.execute_script("document.querySelector('#sale_order_user_id').value = '#{customer.id}'")
    fill_in 'sale_order_tax_rate', with: '0'
    click_button 'Guardar Orden'

    expect(page).to have_content('Orden de venta creada.')
    created_order = SaleOrder.order(:created_at).last
    expect(page).to have_current_path(admin_sale_order_path(created_order))
    expect(created_order.sale_order_items.sole.product).to eq(product)
  end
end
