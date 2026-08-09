# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Carts', type: :request do
  let!(:product) { create(:product) }

  it 'shows products in cart' do
    post cart_items_path, params: { product_id: product.id }
    get cart_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include(product.product_name)
  end

  it 'renders one responsive row, quantity control and remove form per item' do
    post cart_items_path, params: { product_id: product.id }
    get cart_path

    document = Nokogiri::HTML5(response.body)
    row = document.at_css("#cart_item_#{product.id}_brand_new.cart-item-row")

    expect(row).to be_present
    expect(document.css('[data-controller~="cart-item"]').count).to eq(1)
    expect(row.css('[data-cart-item-target="quantity"]').count).to eq(1)
    expect(row.css('.cart-unit-price').count).to eq(1)
    expect(row.css('.cart-line-total').count).to eq(1)
    expect(row.css('.cart-remove-form').count).to eq(1)
    expect(response.body).to include('Total antes de envío')
  end

  it 'renders explicit table semantics and one stable cart status region' do
    post cart_items_path, params: { product_id: product.id }
    get cart_path

    document = Nokogiri::HTML5(response.body)

    expect(document.at_css('table.cart-items-table[role="table"]')).to be_present
    expect(document.css('thead[role="rowgroup"], tbody[role="rowgroup"], tfoot[role="rowgroup"]').count).to eq(3)
    expect(document.at_css('tr.cart-item-row[role="row"] th[role="rowheader"][scope="row"]')).to be_present
    expect(document.css('thead th[role="columnheader"]').count).to eq(5)
    expect(document.css('tr.cart-item-row td[role="cell"]').count).to eq(4)
    expect(document.css('#cart-status[role="status"][aria-live="polite"][aria-atomic="true"]').count).to eq(1)
    expect(document.css('#cart-total[aria-live], #cart-item-count[aria-live], #summary-grand-total[aria-live], .cart-line-total-value[aria-live]')).to be_empty
  end
end
