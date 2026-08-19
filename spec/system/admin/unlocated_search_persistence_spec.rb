# frozen_string_literal: true

require 'rails_helper'

# El operador busca una familia de productos y va agregando varios de ese mismo
# resultado. Antes cada alta borraba el buscador y lo obligaba a repetir la
# búsqueda; ahora la búsqueda se queda quieta y sólo cambia el lote.
RSpec.describe 'Unlocated: search survives adding', :js, type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let!(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }

  let!(:r32) { create(:product, skip_seed_inventory: true, product_name: 'Skyline GT-R R32', product_sku: 'SKY-32') }
  let!(:r34) { create(:product, skip_seed_inventory: true, product_name: 'Skyline GT-R R34', product_sku: 'SKY-34') }
  let!(:gt2000) { create(:product, skip_seed_inventory: true, product_name: 'Skyline 2000GT-R', product_sku: 'SKY-20') }

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
    [r32, r34, gt2000].each do |p|
      6.times { create(:inventory, product: p, status: :available, inventory_location: nil) }
    end
  end

  after { Warden.test_reset! }

  def choose_shelf
    select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: 'batch-location-id'
    click_button 'Seleccionar'
    expect(page).to have_css('#selected-location')
  end

  it 'keeps the term, the results and the location while adding several SKUs' do
    visit admin_inventory_unlocated_path
    choose_shelf

    fill_in 'product-search', with: 'Skyline'
    click_button 'Buscar'

    expect(page).to have_css('#search-results-table tr[data-product-id]', count: 3)

    fill_in "quantity-#{r34.id}", with: '3'
    click_button "add-#{r34.id}"

    # El lote se actualiza...
    expect(page).to have_css("li[data-batch-product-id='#{r34.id}']")
    expect(page).to have_css('#batch-units', text: '3 pieza(s)')

    # ...y la búsqueda sigue exactamente donde estaba.
    expect(page).to have_field('product-search', with: 'Skyline')
    expect(page).to have_css('#search-results-table tr[data-product-id]', count: 3)
    expect(page).to have_css("tr[data-product-id='#{r32.id}']")
    expect(page).to have_css("tr[data-product-id='#{gt2000.id}']")
    expect(page).to have_css('#selected-location', text: 'Estante B03')

    # La cantidad de la fila agregada vuelve a 1, lista para otra.
    expect(page).to have_field("quantity-#{r34.id}", with: '1')

    # Segundo SKU del MISMO resultado, sin volver a buscar.
    fill_in "quantity-#{r32.id}", with: '2'
    click_button "add-#{r32.id}"

    expect(page).to have_css("li[data-batch-product-id='#{r32.id}']")
    expect(page).to have_css("li[data-batch-product-id='#{r34.id}']")
    expect(page).to have_css('#batch-products', text: '2 producto(s)')
    expect(page).to have_css('#batch-units', text: '5 pieza(s)')
    expect(page).to have_field('product-search', with: 'Skyline')
  end

  it 'combines the same product added twice, still without re-searching' do
    visit admin_inventory_unlocated_path
    choose_shelf
    fill_in 'product-search', with: 'SKY-34'
    click_button 'Buscar'

    fill_in "quantity-#{r34.id}", with: '2'
    click_button "add-#{r34.id}"
    expect(page).to have_css('#batch-units', text: '2 pieza(s)')

    fill_in "quantity-#{r34.id}", with: '3'
    click_button "add-#{r34.id}"

    expect(page).to have_css("li[data-batch-product-id='#{r34.id}']", count: 1)
    expect(page).to have_css('#batch-units', text: '5 pieza(s)')
    expect(page).to have_field('product-search', with: 'SKY-34')
  end

  it 'keeps the operator context when the add fails' do
    visit admin_inventory_unlocated_path
    choose_shelf
    fill_in 'product-search', with: 'SKY-34'
    click_button 'Buscar'
    expect(page).to have_css("tr[data-product-id='#{r34.id}']")

    page.execute_script("document.getElementById('quantity-#{r34.id}').removeAttribute('min')")
    fill_in "quantity-#{r34.id}", with: '0'
    click_button "add-#{r34.id}"

    expect(page).to have_content('mayor a cero')
    expect(page).to have_field('product-search', with: 'SKY-34')
    expect(page).to have_css("tr[data-product-id='#{r34.id}']")
    expect(page).to have_css('#selected-location', text: 'Estante B03')
  end
end
