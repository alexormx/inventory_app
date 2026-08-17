# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Catalog filter navigation', type: :system, js: true do
  before do
    driven_by :selenium_chrome_headless
  end

  def current_query
    Rack::Utils.parse_nested_query(URI.parse(page.current_url).query.to_s)
  end

  def expect_complete_filter_state
    expect(current_query).to include(
      'q' => 'Catalog System',
      'categories' => ['Autos'],
      'brands' => ['Tomica'],
      'series' => ['Vintage'],
      'conditions' => ['nuevo'],
      'in_stock' => '1',
      'in_transit' => '1',
      'to_order' => '1'
    )
    expect(page).to have_checked_field('cat-autos', visible: :all)
    expect(page).to have_checked_field('brand-tomica', visible: :all)
    expect(page).to have_checked_field('series-vintage', visible: :all)
    expect(page).to have_checked_field('f-cond-nuevo', visible: :all)
    expect(page).to have_css('.availability-chip.active', text: 'En stock')
    expect(page).to have_css('.availability-chip.active', text: 'En tránsito')
    expect(page).to have_css('.availability-chip.active', text: 'Sobre pedido')
  end

  it 'keeps the complete state, announces completion and makes one request per sort after repeat visits' do
    inexpensive = create(
      :product,
      product_name: 'Catalog System Inexpensive',
      category: 'Autos',
      brand: 'Tomica',
      series: 'Vintage',
      selling_price: 100,
      backorder_allowed: true
    )
    expensive = create(
      :product,
      product_name: 'Catalog System Expensive',
      category: 'Autos',
      brand: 'Tomica',
      series: 'Vintage',
      selling_price: 200,
      backorder_allowed: true
    )
    [inexpensive, expensive].each do |product|
      product.inventories.available.first.update!(item_condition: :brand_new)
    end

    filtered_path = catalog_path(
      q: 'Catalog System', categories: ['Autos'], brands: ['Tomica'],
      series: ['Vintage'], conditions: ['nuevo'], in_stock: '1',
      in_transit: '1', to_order: '1'
    )

    visit filtered_path
    visit root_path
    visit filtered_path
    visit root_path
    visit filtered_path
    expect_complete_filter_state

    page.execute_script('performance.clearResourceTimings()')

    find('#header-sort-form select[name="sort"]').select('Precio ↑')

    expect(find('#product-grid-content .product-card-wrapper:first-child')).to have_text(inexpensive.product_name)
    expect(current_query).to include('sort' => 'price_asc')
    expect(current_query).not_to have_key('page')
    catalog_requests = page.evaluate_script(<<~JS)
      performance.getEntriesByType("resource").filter((entry) => {
        return new URL(entry.name).pathname === "/catalog"
      }).length
    JS
    expect(catalog_requests).to eq(1)
    expect(page).to have_css(
      '#catalog-results-announcer',
      text: 'Actualización finalizada: 2 productos.',
      visible: :all
    )
    expect(page).to have_css('form.catalog-sidebar-filters input[name="sort"][value="price_asc"]', count: 2, visible: :all)
    expect_complete_filter_state

    page.go_back
    expect(find('#product-grid-content .product-card-wrapper:first-child')).to have_text(expensive.product_name)
    expect(current_query).not_to have_key('sort')
    expect_complete_filter_state

    page.go_forward
    expect(find('#product-grid-content .product-card-wrapper:first-child')).to have_text(inexpensive.product_name)
    expect(current_query).to include('sort' => 'price_asc')

    page.refresh
    expect(find('#product-grid-content .product-card-wrapper:first-child')).to have_text(inexpensive.product_name)
    expect_complete_filter_state
  end

  it 'preserves filters through pagination, back, forward and a subsequent filter change' do
    create_list(
      :product,
      25,
      skip_seed_inventory: true,
      category: 'Autos',
      brand: 'Tomica',
      series: 'Vintage',
      backorder_allowed: true
    )
    filtered_path = catalog_path(
      q: 'Sample', categories: ['Autos'], brands: ['Tomica'],
      series: ['Vintage'], to_order: '1', sort: 'name_asc'
    )

    visit filtered_path
    accept_cookies_if_present
    within('turbo-frame#products_grid') do
      find('.catalog-pagination .page-link', text: '2', exact_text: true).click
    end

    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 1)
    expect(current_query).to include(
      'q' => 'Sample', 'categories' => ['Autos'], 'brands' => ['Tomica'],
      'series' => ['Vintage'], 'to_order' => '1', 'sort' => 'name_asc', 'page' => '2'
    )

    page.go_back
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
    expect(current_query).not_to have_key('page')

    page.go_forward
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 1)
    expect(current_query).to include('page' => '2')

    find('#header-sort-form select[name="sort"]').select('Más recientes')
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
    expect(current_query).not_to have_key('page')
    expect(current_query).to include(
      'q' => 'Sample', 'categories' => ['Autos'], 'brands' => ['Tomica'],
      'series' => ['Vintage'], 'to_order' => '1', 'sort' => 'newest'
    )
  end

  it 'announces a completed empty result update from one stable live region' do
    create(:product)

    visit catalog_path(q: 'resultado-imposible')

    expect(page).to have_css('.empty-state h2', text: 'Sin resultados')
    expect(page).to have_css(
      '#catalog-results-announcer',
      text: 'Actualización finalizada: no hay resultados.',
      visible: :all
    )
    expect(page).to have_css('#catalog [aria-live="polite"]', count: 1, visible: :all)
    expect(page).to have_no_css('turbo-frame#products_grid [aria-live], turbo-frame#products_grid [role="status"]')
  end
end
