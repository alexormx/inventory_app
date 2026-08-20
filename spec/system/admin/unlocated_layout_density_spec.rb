# frozen_string_literal: true

require 'rails_helper'

# La pantalla tiene que caber. El operador trabaja mirando cuatro cosas a la vez
# —dónde está, qué busca, qué hay ya guardado ahí y qué lleva juntado— así que en
# un escritorio normal las cuatro deben verse sin perseguir el scroll.
RSpec.describe 'Unlocated layout density', :js, type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let!(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }
  let(:product) { create(:product, skip_seed_inventory: true, product_name: 'Skyline Nueva', product_sku: 'NEW-111') }
  let(:stored) { create(:product, skip_seed_inventory: true, product_name: 'Supra Guardada', product_sku: 'OLD-222') }

  def resize_to(width, height)
    page.current_window.resize_to(width, height)
  end

  def page_metrics
    page.evaluate_script(<<~JS)
      ({
        scrollWidth: document.documentElement.scrollWidth,
        clientWidth: document.documentElement.clientWidth
      })
    JS
  end

  def expect_no_horizontal_overflow
    metrics = page_metrics
    expect(metrics['scrollWidth']).to(
      be <= metrics['clientWidth'],
      "desbordamiento horizontal: #{metrics.inspect}"
    )
  end

  def prepare_screen
    visit admin_inventory_unlocated_path
    select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: 'batch-location-id'
    click_button 'Seleccionar'
    expect(page).to have_css('#selected-location', text: 'Estante B03')
    fill_in 'product-search', with: 'Skyline'
    click_button 'Buscar'
    expect(page).to have_css("tr[data-product-id='#{product.id}']")
  end

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
    Array.new(6) { create(:inventory, product: product, status: :available, inventory_location: nil) }
    Array.new(3) { create(:inventory, product: stored, status: :available, inventory_location: shelf) }
  end

  after { Warden.test_reset! }

  # Los cuatro paneles del flujo, con sus anclas de Turbo.
  %w[
    selected-location-panel
    product-search-panel
    location-current-inventory
    location-batch-panel
  ].each do |panel|
    it "muestra ##{panel} en escritorio" do
      resize_to(1440, 1000)
      prepare_screen

      expect(page).to have_css("##{panel}")
    end
  end

  it 'cabe entero en un escritorio de 1440 sin desbordarse' do
    resize_to(1440, 1000)
    prepare_screen

    expect_no_horizontal_overflow
  end

  it 'reparte en dos columnas: el lote queda al lado de la búsqueda, no debajo' do
    resize_to(1440, 1000)
    prepare_screen

    search_box = page.evaluate_script("document.getElementById('product-search-panel').getBoundingClientRect().right")
    batch_left = page.evaluate_script("document.getElementById('location-batch-panel').getBoundingClientRect().left")

    expect(batch_left).to be >= search_box
  end

  it 'sigue sin desbordarse en un portátil de 1280' do
    resize_to(1280, 800)
    prepare_screen

    expect_no_horizontal_overflow
    expect(page).to have_css('#location-current-inventory')
    expect(page).to have_css('#location-batch-panel')
  end

  it 'se apila en tableta sin desbordarse y con el botón Agregar utilizable' do
    resize_to(820, 1100)
    prepare_screen

    expect_no_horizontal_overflow

    # Apilado: el lote deja de estar a la derecha y pasa debajo.
    search_bottom = page.evaluate_script("document.getElementById('product-search-panel').getBoundingClientRect().bottom")
    batch_top = page.evaluate_script("document.getElementById('location-batch-panel').getBoundingClientRect().top")
    expect(batch_top).to be >= search_bottom

    # Y el botón sigue siendo alcanzable de verdad, no sólo presente.
    fill_in "quantity-#{product.id}", with: '2'
    click_button "add-#{product.id}"
    expect(page).to have_css('#batch-units', text: '2 pieza(s)')
  end

  # Las miniaturas son para reconocer la caja de un vistazo, no para lucirse.
  it 'mantiene las miniaturas compactas en las tres listas' do
    resize_to(1440, 1000)
    prepare_screen
    fill_in "quantity-#{product.id}", with: '2'
    click_button "add-#{product.id}"
    expect(page).to have_css('#batch-units', text: '2 pieza(s)')

    %w[
      #search-results-table
      #location-batch-panel
      #current-location-lines
    ].each do |container|
      heights = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('#{container} [style*="width:"]'))
          .map((el) => el.getBoundingClientRect().height)
          .filter((h) => h > 0)
      JS
      expect(heights).to all(be <= 60), "miniaturas demasiado grandes en #{container}: #{heights.inspect}"
    end
  end
end
