# frozen_string_literal: true

require 'rails_helper'

# El recorrido real del almacén: buscar el producto, escribir cuántas piezas
# encontró, elegir el estante y asignar. En ningún momento se escribe ni se ve
# un Inventory ID.
RSpec.describe 'Admin assigns a location by product and quantity', :js, type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:product) do
    create(:product, skip_seed_inventory: true,
                     product_name: 'Tomica Nissan Skyline GT-R', product_sku: 'TOM-123')
  end
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let!(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
    12.times { create(:inventory, product: product, status: :available, inventory_location: nil) }
    2.times { create(:inventory, product: product, status: :reserved, inventory_location: nil) }
  end

  after { Warden.test_reset! }

  it 'locates the quantity the operator found, without naming any Inventory id' do
    visit admin_inventory_unlocated_path

    expect(page).to have_css('#unlocated-products-table')

    fill_in 'q', with: 'TOM-123'
    click_button 'Buscar'

    expect(page).to have_content('Tomica Nissan Skyline GT-R')
    # 12 disponibles + 2 apartadas = 14 asignables
    expect(page).to have_css("tr[data-product-id='#{product.id}'] [data-assignable='14']")

    within("tr[data-product-id='#{product.id}']") do
      fill_in "quantity-#{product.id}", with: '5'
      select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: "location-#{product.id}"
      click_button 'Asignar'
    end

    expect(page).to have_content('5 unidad(es)')
    expect(page).to have_content('Estante B03')

    # Quedan 9 asignables y la base confirma exactamente 5 ubicadas.
    expect(page).to have_css("tr[data-product-id='#{product.id}'] [data-assignable='9']")
    expect(product.inventories.where(inventory_location_id: shelf.id).count).to eq(5)
    expect(InventoryEvent.where(event_type: 'physical_inventory_verification').count).to eq(5)
  end

  it 'refuses the whole batch when more units are requested than exist' do
    visit admin_inventory_unlocated_path

    within("tr[data-product-id='#{product.id}']") do
      fill_in "quantity-#{product.id}", with: '99'
      select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: "location-#{product.id}"
      # El input tiene max=14; se quita para probar la defensa del servidor.
      page.execute_script("document.getElementById('quantity-#{product.id}').removeAttribute('max')")
      click_button 'Asignar'
    end

    expect(page).to have_content('No se asignó ninguna')
    expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
  end
end
