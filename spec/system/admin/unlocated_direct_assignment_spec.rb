# frozen_string_literal: true

require 'rails_helper'

# El recorrido real de bodega, ya sin pantalla de revisión: el operador se para
# frente al estante, junta lo que trae en la mano y lo deja ahí de una vez.
RSpec.describe 'Admin assigns a whole batch directly', :js, type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let!(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }

  let(:existing_a) { create(:product, skip_seed_inventory: true, product_name: 'Vieja Uno', product_sku: 'OLD-1') }
  let(:existing_b) { create(:product, skip_seed_inventory: true, product_name: 'Vieja Dos', product_sku: 'OLD-2') }
  let(:skyline) { create(:product, skip_seed_inventory: true, product_name: 'Skyline Nueva', product_sku: 'NEW-1') }
  let(:supra) { create(:product, skip_seed_inventory: true, product_name: 'Skyline Supra', product_sku: 'NEW-2') }
  let(:civic) { create(:product, skip_seed_inventory: true, product_name: 'Skyline Civic', product_sku: 'NEW-3') }

  def stock(product, count, location: nil)
    Array.new(count) { create(:inventory, product: product, status: :available, inventory_location: location) }
  end

  def choose_shelf
    select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: 'batch-location-id'
    click_button 'Seleccionar'
    expect(page).to have_css('#selected-location', text: 'Estante B03')
  end

  def search(term)
    fill_in 'product-search', with: term
    click_button 'Buscar'
  end

  def mark_window = page.execute_script("window.__noReload = 'kept'")
  def expect_no_reload = expect(page.evaluate_script('window.__noReload')).to eq('kept')

  before do
    driven_by :selenium_chrome_headless
    login_as admin, scope: :user
    stock(existing_a, 4, location: shelf)
    stock(existing_b, 2, location: shelf)
  end

  it 'junta varios modelos y los deja en el estante sin pasar por revisión' do
    stock(skyline, 5)
    stock(supra, 3)
    stock(civic, 2)

    visit admin_inventory_unlocated_path
    choose_shelf
    expect(page).to have_css('#current-location-units', text: '6 pieza(s)')

    search 'Skyline'
    # "Agregar todas las disponibles": el servidor decide cuántas son todas.
    click_button(id: "add-all-#{skyline.id}")
    expect(page).to have_css('#batch-units', text: '5 pieza(s)')

    fill_in "quantity-#{supra.id}", with: 2
    click_button(id: "add-#{supra.id}")
    expect(page).to have_css('#batch-units', text: '7 pieza(s)')

    fill_in "quantity-#{civic.id}", with: 1
    click_button(id: "add-#{civic.id}")
    expect(page).to have_css('#batch-products', text: '3 producto(s)')
    expect(page).to have_css('#batch-units', text: '8 pieza(s)')

    # Nada ha tocado la base todavía: el estante sigue con lo suyo.
    expect(page).to have_css('#current-location-units', text: '6 pieza(s)')
    expect(Inventory.where(inventory_location_id: shelf.id).count).to eq(6)

    mark_window
    click_button(id: 'assign-batch')

    # Sin navegar: el lote se vacía y el estante crece.
    expect(page).to have_content('8 unidades fueron asignadas')
    expect(page).to have_css('#batch-empty')
    expect(page).to have_css('#current-location-units', text: '14 pieza(s)')
    expect_no_reload

    expect(page).to have_css('#selected-location', text: 'Estante B03')
    expect(page).to have_field('product-search', with: 'Skyline')

    expect(skyline.inventories.where(inventory_location_id: shelf.id).count).to eq(5)
    expect(supra.inventories.where(inventory_location_id: shelf.id).count).to eq(2)
    expect(civic.inventories.where(inventory_location_id: shelf.id).count).to eq(1)

    # Y los resultados se actualizan: lo que ya quedó ubicado desaparece de la
    # lista de "sin ubicar", que es de donde salen estas filas.
    expect(page).to have_no_css("#result-row-#{skyline.id}")
  end

  it 'nunca deja el lote por encima de lo que hay para ubicar' do
    stock(skyline, 5)

    visit admin_inventory_unlocated_path
    choose_shelf
    search 'Skyline'

    fill_in "quantity-#{skyline.id}", with: 3
    click_button(id: "add-#{skyline.id}")
    expect(page).to have_css('#batch-units', text: '3 pieza(s)')
    expect(page).to have_css("#remaining-#{skyline.id}", text: 'Restantes: 2')

    # El max del input ya bajó a 2, así que el navegador solo bloquearía el envío.
    # Se relaja para comprobar que quien de verdad rechaza es el SERVIDOR.
    page.execute_script("document.getElementById('quantity-#{skyline.id}').removeAttribute('max')")
    fill_in "quantity-#{skyline.id}", with: 3
    click_button(id: "add-#{skyline.id}")

    expect(page).to have_content('sólo puedes agregar 2 más')
    expect(page).to have_css('#batch-units', text: '3 pieza(s)')

    # "Todas las disponibles" completa exactamente hasta el inventario real.
    click_button(id: "add-all-#{skyline.id}")
    expect(page).to have_css('#batch-units', text: '5 pieza(s)')
    expect(page).to have_css("#remaining-#{skyline.id}", text: 'Restantes: 0')
    expect(page).to have_css("#all-pending-#{skyline.id}")
  end

  it 'muestra los tres números y los mantiene al día al agregar' do
    stock(skyline, 10)

    visit admin_inventory_unlocated_path
    choose_shelf
    search 'Skyline'

    expect(page).to have_css("#assignable-#{skyline.id}", text: 'Asignables: 10')
    expect(page).to have_css("#pending-#{skyline.id}", text: 'En lote: 0')
    expect(page).to have_css("#remaining-#{skyline.id}", text: 'Restantes: 10')

    mark_window
    fill_in "quantity-#{skyline.id}", with: 3
    click_button(id: "add-#{skyline.id}")

    expect(page).to have_css("#pending-#{skyline.id}", text: 'En lote: 3')
    expect(page).to have_css("#remaining-#{skyline.id}", text: 'Restantes: 7')
    expect(page).to have_css("#assignable-#{skyline.id}", text: 'Asignables: 10')
    # Sólo se repintó esa fila: la búsqueda sigue intacta.
    expect_no_reload
    expect(page).to have_field('product-search', with: 'Skyline')
  end
end
