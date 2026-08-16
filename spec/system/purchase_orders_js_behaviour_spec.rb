# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Purchase Order JS behaviour', :system_smoke, type: :system, js: true do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let!(:supplier) { create(:user, :supplier, name: 'Proveedor de prueba') }
  let!(:product) do
    create(
      :product,
      product_name: 'Producto para orden de compra',
      product_sku: 'PO-JS-001',
      selling_price: 100.0,
      weight_gr: 250,
      length_cm: 10,
      width_cm: 5,
      height_cm: 4
    )
  end

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

  it 'keeps product selection idempotent across Turbo loads and updates line totals' do
    visit new_admin_purchase_order_path

    expect(page).to have_css('#order-items-table')

    select_product(product)
    expect(page).to have_css('#order-items-table tbody tr.purchase-item-row', count: 1)

    find('#order-items-table tbody tr.purchase-item-row .remove-item').click
    expect(page).to have_no_css('#order-items-table tbody tr.purchase-item-row')

    page.execute_script(<<~JS)
      document.dispatchEvent(new Event('turbo:load'));
      document.dispatchEvent(new Event('turbo:load'));
      document.dispatchEvent(new Event('turbo:before-cache'));
      document.dispatchEvent(new Event('turbo:load'));
    JS

    select_product(product)
    expect(page).to have_css('#order-items-table tbody tr.purchase-item-row', count: 1)

    row = find('#order-items-table tbody tr.purchase-item-row')
    row.find('.item-qty').fill_in(with: '2')
    row.find('.item-unit-cost').fill_in(with: '150')

    expect(row.find('.item-total-cost').value).to eq('300.00')
    expect(page).to have_css('#display-subtotal', text: '$300.00')
    expect(page).to have_css('#summary-total-qty', text: '2')

    row.find('.remove-item').click
    expect(page).to have_no_css('#order-items-table tbody tr.purchase-item-row')
    expect(page).to have_css('#summary-items-count', text: '0')
  end

  it 'submits the purchase order with the selected product' do
    visit new_admin_purchase_order_path

    select_product(product)
    page.execute_script("document.querySelector('#purchase_order_user_id').value = '#{supplier.id}'")
    find('#purchase_order_expected_delivery_date').set(5.days.from_now.to_date.iso8601)
    find('#order-items-table tbody tr.purchase-item-row .item-unit-cost').fill_in(with: '125')
    click_button 'Guardar Orden'

    expect(page).to have_content('Purchase order created successfully.')
    expect(page).to have_current_path(admin_purchase_orders_path)

    created_order = PurchaseOrder.order(:created_at).last
    expect(created_order.user).to eq(supplier)
    expect(created_order.purchase_order_items.sole.product).to eq(product)
    expect(created_order.purchase_order_items.sole.unit_cost).to eq(125)
  end
end
