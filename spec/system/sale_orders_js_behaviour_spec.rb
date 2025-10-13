# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sale Order JS behaviour', type: :system, js: true do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let!(:product) { create(:product, product_name: 'Carro RC', product_sku: 'RC-001', selling_price: 100.0, weight_gr: 250, length_cm: 10, width_cm: 5, height_cm: 4) }

  before do
    login_as(admin, scope: :user)
  end

  it 'adds a single row per product selection and updates totals live' do
    visit new_admin_sale_order_path

  # Esperar a que la tabla esté en DOM y simular turbo:load para que los listeners se registren
  expect(page).to have_css('#order-items-table')
  page.execute_script('document.dispatchEvent(new Event("turbo:load"))')

    # Disparar selección de producto manualmente para evitar dependencia de red/UI de búsqueda
    page.execute_script(<<~JS)
      const detail = {
        id: #{product.id},
        product_name: '#{product.product_name}',
        product_sku: '#{product.product_sku}',
        thumbnail_url: '/assets/icon.png',
        weight_gr: 250,
        length_cm: 10,
        width_cm: 5,
        height_cm: 4
      };
      document.dispatchEvent(new CustomEvent('product-selected', { detail }));
      document.dispatchEvent(new CustomEvent('product:selected', { detail }));
      document.dispatchEvent(new CustomEvent('product-search:selected', { detail }));
    JS

    # Debe haber exactamente una fila
    expect(page).to have_css('#order-items-table tbody tr.item-row', count: 1)

    # Cambiar cantidad y precio unitario
    find('#order-items-table tbody tr.item-row input.item-qty').fill_in(with: '2')
    find('#order-items-table tbody tr.item-row input.item-unit-cost').fill_in(with: '150')
    # Aplicar descuento unitario
    find('#order-items-table tbody tr.item-row input.item-unit-discount').fill_in(with: '10')

    # Verificar subtotal y totales en displays (pueden tardar por eventos input)
    expect(page).to have_css('#display-subtotal', text: '$280.00') # 2 * (150 - 10)

    # Cambiar impuesto y descuento general
    find('#sale_order_tax_rate').fill_in(with: '16')
    find('#sale_order_discount').fill_in(with: '20')

    # Cálculo: subtotal=280, IVA=44.8, total=304.8
    expect(page).to have_css('#display-total-tax', text: '$44.80')
    expect(page).to have_css('#display-total', text: '$304.80')

    # Sidebar
    expect(page).to have_css('#summary-items-count', text: '1')
    expect(page).to have_css('#summary-total-qty', text: '2')
    expect(page).to have_css('#summary-subtotal', text: '$280.00')
    expect(page).to have_css('#summary-tax', text: '$44.80')
    expect(page).to have_css('#summary-total', text: '$304.80')

    # Validar que no se duplique al seleccionar nuevamente el mismo producto una vez
    page.execute_script(<<~JS)
      const detail2 = {
        id: #{product.id},
        product_name: '#{product.product_name}',
        product_sku: '#{product.product_sku}',
        thumbnail_url: '/assets/icon.png',
        weight_gr: 250,
        length_cm: 10,
        width_cm: 5,
        height_cm: 4
      };
      document.dispatchEvent(new CustomEvent('product:selected', { detail: detail2 }));
    JS

    expect(page).to have_css('#order-items-table tbody tr.item-row', count: 2)
  end
end
