# frozen_string_literal: true

require 'rails_helper'
require 'cgi'

RSpec.describe 'Catalog browsing', type: :request do
  let(:user) { create(:user) }

  before do
    host! 'localhost'
    sign_in user
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def submitted_parameters(form)
    pairs = form.css('input[name]:not([disabled])').map { |input| [input['name'], input['value'].to_s] }
    form.css('select[name]').each do |select|
      option = select.at_css('option[selected]') || select.at_css('option')
      pairs << [select['name'], option['value'].presence || option.text]
    end
    Rack::Utils.parse_nested_query(URI.encode_www_form(pairs))
  end

  def header_sort_parameters
    submitted_parameters(document.at_css('form#header-sort-form'))
  end

  describe 'GET /catalog' do
    it 'lists products with default sort (newest)' do
      old = create(:product, created_at: 2.days.ago)
      recent = create(:product, created_at: 1.hour.ago)

      get catalog_path

      expect(response).to have_http_status(:ok)
      expect(response.body.index(recent.product_name)).to be < response.body.index(old.product_name)
    end

    it 'filters by query across name, category and brand' do
      match = create(:product, product_name: 'Tomica Supra GT')
      excluded = create(:product, brand: 'HotWheels', product_name: 'Generic Car')

      get catalog_path, params: { q: 'tomica' }

      expect(response.body).to include(match.product_name)
      expect(response.body).not_to include(excluded.product_name)
    end

    it 'supports sorting by price asc/desc and name asc' do
      cheap = create(:product, selling_price: 10)
      pricey = create(:product, selling_price: 20)
      alpha = create(:product, product_name: 'Alpha Zed')
      zulu = create(:product, product_name: 'Zulu Car')

      get catalog_path, params: { sort: 'price_asc' }
      expect(response.body.index(cheap.product_name)).to be < response.body.index(pricey.product_name)

      get catalog_path, params: { sort: 'price_desc' }
      expect(response.body.index(pricey.product_name)).to be < response.body.index(cheap.product_name)

      get catalog_path, params: { sort: 'name_asc' }
      expect(response.body.index(alpha.product_name)).to be < response.body.index(zulu.product_name)
    end

    it 'filters by categories and brands' do
      match = create(:product, category: 'Autos', brand: 'Tomica')
      excluded = create(:product, category: 'Aviones', brand: 'Takara')

      get catalog_path, params: { categories: ['Autos'], brands: ['Tomica'] }

      expect(response.body).to include(match.product_name)
      expect(response.body).not_to include(excluded.product_name)
    end

    it 'filters by series and conditions' do
      match = create(:product, series: 'Vintage')
      match.inventories.available.first.update!(item_condition: :brand_new)
      excluded = create(:product, series: 'Premium')
      excluded.inventories.available.first.update!(item_condition: :loose)

      get catalog_path, params: { series: ['Vintage'], conditions: ['nuevo'] }

      expect(response.body).to include(match.product_name)
      expect(response.body).not_to include(excluded.product_name)
    end

    it 'filters by price range' do
      low = create(:product, selling_price: 5)
      mid = create(:product, selling_price: 10)
      high = create(:product, selling_price: 50)

      get catalog_path, params: { price_min: 6, price_max: 20 }

      expect(response.body).to include(mid.product_name)
      expect(response.body).not_to include(low.product_name)
      expect(response.body).not_to include(high.product_name)
    end

    it 'combines availability filters with OR and uses to_order as the public contract' do
      stocked = create(:product)
      transit = create(:product, skip_seed_inventory: true)
      create(:inventory, product: transit, status: :in_transit)
      to_order = create(:product, skip_seed_inventory: true, backorder_allowed: true)

      get catalog_path, params: { in_stock: '1', in_transit: '1' }

      expect(response.body).to include(stocked.product_name, transit.product_name)
      expect(response.body).not_to include(to_order.product_name)

      get catalog_path, params: { to_order: '1' }

      expect(response.body).to include(to_order.product_name)
      expect(response.body).not_to include(stocked.product_name)
      expect(response.body).not_to include(transit.product_name)
    end

    it 'renders both sidebar forms with the same active availability state' do
      product = create(:product, skip_seed_inventory: true, backorder_allowed: true)
      create(:inventory, product: product, status: :in_transit)

      get catalog_path, params: { in_transit: '1', to_order: '1' }

      expect(document.css('form.catalog-sidebar-filters input[name="in_transit"][value="1"]').size).to eq(2)
      expect(document.css('form.catalog-sidebar-filters input[name="to_order"][value="1"]').size).to eq(2)
    end

    it 'serializes search in the complete sort form' do
      create(:product, product_name: 'Supra Search')

      get catalog_path, params: { q: 'Supra' }

      expect(header_sort_parameters).to include('q' => 'Supra', 'sort' => 'newest')
    end

    it 'serializes category and brand in the complete sort form' do
      create(:product, category: 'Autos', brand: 'Tomica')

      get catalog_path, params: { categories: ['Autos'], brands: ['Tomica'] }

      expect(header_sort_parameters).to include('categories' => ['Autos'], 'brands' => ['Tomica'])
    end

    it 'serializes series and conditions in the complete sort form' do
      product = create(:product, series: 'Vintage')
      product.inventories.available.first.update!(item_condition: :brand_new)

      get catalog_path, params: { series: ['Vintage'], conditions: ['nuevo'] }

      expect(header_sort_parameters).to include('series' => ['Vintage'], 'conditions' => ['nuevo'])
    end

    it 'serializes all three availability filters in the complete sort form' do
      create(:product, backorder_allowed: true)

      get catalog_path, params: { in_stock: '1', in_transit: '1', to_order: '1' }

      expect(header_sort_parameters).to include(
        'in_stock' => '1',
        'in_transit' => '1',
        'to_order' => '1'
      )
    end

    it 'removes page when enabling a chip or submitting a new sort', :aggregate_failures do
      create(:product)

      get catalog_path, params: { page: '3', q: 'Sample' }

      chip_href = document.at_css('a[aria-label="Filtrar por En stock"]')['href']
      chip_params = Rack::Utils.parse_nested_query(URI.parse(chip_href).query.to_s)
      expect(chip_params).not_to have_key('page')
      expect(header_sort_parameters).not_to have_key('page')
      expect(header_sort_parameters['q']).to eq('Sample')
    end

    it 'keeps every filter in pagination links' do
      create_list(
        :product,
        25,
        skip_seed_inventory: true,
        category: 'Autos',
        brand: 'Tomica',
        series: 'Vintage',
        backorder_allowed: true
      )
      filters = {
        q: 'Sample', categories: ['Autos'], brands: ['Tomica'], series: ['Vintage'],
        price_min: '50', price_max: '250', to_order: '1', sort: 'name_asc'
      }

      get catalog_path, params: filters

      next_href = document.at_css('.catalog-pagination a[rel="next"]')['href']
      next_params = Rack::Utils.parse_nested_query(URI.parse(next_href).query.to_s)
      expect(next_params).to include(
        'q' => 'Sample', 'categories' => ['Autos'], 'brands' => ['Tomica'],
        'series' => ['Vintage'], 'price_min' => '50', 'price_max' => '250',
        'to_order' => '1', 'sort' => 'name_asc', 'page' => '2'
      )
    end

    it 'keeps the canonical URL limited to indexable catalog dimensions' do
      create(:product, category: 'Autos', brand: 'Tomica', series: 'Vintage')

      get catalog_path, params: {
        categories: ['Autos'], brands: ['Tomica'], series: ['Vintage'],
        q: 'Sample', conditions: ['nuevo'], in_stock: '1', sort: 'price_asc', page: '2'
      }

      canonical = CGI.unescapeHTML(document.at_css('link[rel="canonical"]')['href'])
      canonical_params = Rack::Utils.parse_nested_query(URI.parse(canonical).query.to_s)
      expect(canonical_params).to eq(
        'categories' => ['Autos'], 'brands' => ['Tomica'], 'series' => ['Vintage']
      )
      expect(document.at_css('meta[name="robots"]')['content']).to eq('noindex, follow')
    end

    it 'ignores unknown, legacy, malformed and empty parameters without leaking them into forms' do
      product = create(:product)

      get catalog_path, params: {
        unknown: 'value', backorder: '1', preorder: '1', q: '', categories: [''],
        conditions: ['invalid'], price_min: 'not-a-price', in_stock: '0', sort: 'invalid', page: 'invalid'
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.product_name)
      expect(header_sort_parameters).to eq('sort' => 'newest')
      expect(document.at_css('select[name="sort"] option[selected][value="newest"]')).to be_present
      expect(document.css('.active-filters-chips')).to be_empty
      expect(document.css('input[name="price_min"][value="not-a-price"]')).to be_empty
    end

    it 'omits empty search and page from the clear-all URL' do
      create(:product, category: 'Autos')

      get catalog_path, params: { q: '', categories: ['Autos'], sort: 'name_asc', page: '2' }

      clear_link = document.css('.catalog-results-clear').find { |link| link.text.include?('Limpiar filtros') }
      clear_href = clear_link['href']
      clear_params = Rack::Utils.parse_nested_query(URI.parse(clear_href).query.to_s)
      expect(clear_params).to eq('sort' => 'name_asc')
    end

    it 'renders a semantic empty state and one stable completion announcement', :aggregate_failures do
      get catalog_path, params: { q: 'no-existe-este-producto' }

      frame = document.at_css('turbo-frame#products_grid')
      announcer = document.at_css('#catalog-results-announcer')
      expect(document.at_css('.empty-state h2')&.text).to include('Sin resultados')
      expect(frame['data-turbo-action']).to eq('advance')
      expect(announcer['aria-live']).to eq('polite')
      expect(announcer.ancestors).not_to include(frame)
      expect(frame.css('[role="status"], [role="text"], [aria-live]').size).to eq(0)
      expect(frame.at_css('[data-results-announcement]')['data-results-announcement']).to eq(
        'Actualización finalizada: no hay resultados.'
      )
    end
  end
end
