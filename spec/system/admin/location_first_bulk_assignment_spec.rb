# frozen_string_literal: true

require 'rails_helper'

# El recorrido real: el operador se para frente a un estante, busca lo que trae
# en la mano, lo va agregando, revisa y confirma una sola vez.
RSpec.describe 'Admin assigns a whole batch to one location', :js, type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let!(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }

  let(:product_a) { create(:product, skip_seed_inventory: true, product_name: 'Tomica Skyline GT-R', product_sku: 'TOM-123') }
  let(:product_b) { create(:product, skip_seed_inventory: true, product_name: 'Tomica Supra', product_sku: 'TOM-555') }
  let(:product_c) { create(:product, skip_seed_inventory: true, product_name: 'Tomica Civic Type R', product_sku: 'TOM-900') }

  def stock(product, count)
    Array.new(count) { create(:inventory, product: product, status: :available, inventory_location: nil) }
  end

  def choose_shelf
    select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: 'batch-location-id'
    click_button 'Seleccionar'
  end

  def add_product(product, quantity)
    fill_in 'product-search', with: product.product_sku
    click_button 'Buscar'
    expect(page).to have_css("tr[data-product-id='#{product.id}']")
    fill_in "quantity-#{product.id}", with: quantity.to_s
    click_button "add-#{product.id}"
  end

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
    stock(product_a, 10)
    stock(product_b, 8)
    stock(product_c, 6)
  end

  after { Warden.test_reset! }

  it 'picks the location once, collects several SKUs and confirms the whole batch' do
    visit admin_inventory_unlocated_path

    # Paso 1: la ubicación primero.
    choose_shelf
    expect(page).to have_css('#selected-location', text: 'Estante B03')

    # Paso 2 y 3: ir agregando lo que se acomoda en ese estante.
    add_product(product_a, 5)
    add_product(product_b, 3)
    add_product(product_c, 2)

    expect(page).to have_css('#batch-products', text: '3 producto(s)')
    expect(page).to have_css('#batch-units', text: '10 pieza(s)')

    # Paso 4: revisar antes de escribir nada.
    click_link 'Revisar asignación'
    expect(page).to have_css('#review-location', text: 'Estante B03')
    expect(page).to have_css('#review-lines tr[data-review-product-id]', count: 3)
    expect(page).to have_css('#review-total', text: '10 piezas')
    expect(Inventory.where.not(inventory_location_id: nil)).to be_empty

    # Paso 5: una sola confirmación para todo el lote.
    click_button(id: 'confirm-batch')

    expect(page).to have_content('10 unidades fueron asignadas')
    expect(page).to have_content('Estante B03')

    expect(product_a.inventories.where(inventory_location_id: shelf.id).count).to eq(5)
    expect(product_b.inventories.where(inventory_location_id: shelf.id).count).to eq(3)
    expect(product_c.inventories.where(inventory_location_id: shelf.id).count).to eq(2)
    expect(InventoryEvent.where(event_type: 'physical_inventory_verification').count).to eq(10)

    # Un solo id de lote correlaciona las 10 filas.
    batch_ids = InventoryEvent.all.map { |e| e['metadata']['assignment_batch_id'] }.uniq
    expect(batch_ids.size).to eq(1)
    expect(batch_ids.first).to be_present

    # El lote queda vacío tras confirmar.
    expect(page).to have_css('#batch-empty')
  end

  it 'writes nothing when one product no longer has enough stock' do
    visit admin_inventory_unlocated_path
    choose_shelf
    add_product(product_a, 5)
    add_product(product_b, 3)

    click_link 'Revisar asignación'

    # Otro operador se lleva casi todo el Supra justo antes de confirmar.
    Inventories::LocationAssignment.fifo_scope(product_b.id).limit(6)
                                   .each { |i| i.update!(inventory_location: shelf) }

    click_button(id: 'confirm-batch')

    expect(page).to have_content('No se realizó ninguna asignación')
    expect(page).to have_content('Tomica Supra')
    expect(product_a.inventories.where(inventory_location_id: shelf.id)).to be_empty
  end

  it 'combines a product added twice and lets it be removed' do
    visit admin_inventory_unlocated_path
    choose_shelf

    add_product(product_a, 3)
    add_product(product_a, 2)
    expect(page).to have_css("li[data-batch-product-id='#{product_a.id}']", count: 1)
    expect(page).to have_css('#batch-units', text: '5 pieza(s)')

    add_product(product_b, 4)
    expect(page).to have_css('#batch-products', text: '2 producto(s)')

    click_button(id: "batch-remove-#{product_b.id}")
    expect(page).to have_css('#batch-products', text: '1 producto(s)')
    expect(page).to have_no_css("li[data-batch-product-id='#{product_b.id}']")
  end

  # Encadenar SKUs es el gesto normal: agregar, teclear el siguiente, agregar.
  it 'clears the search after each add so the next SKU can be typed straight away' do
    visit admin_inventory_unlocated_path
    choose_shelf

    fill_in 'product-search', with: product_a.product_sku
    click_button 'Buscar'
    fill_in "quantity-#{product_a.id}", with: '5'
    click_button "add-#{product_a.id}"

    expect(page).to have_css("li[data-batch-product-id='#{product_a.id}']")
    # El buscador queda vacío y con el foco puesto, listo para el siguiente SKU.
    expect(page).to have_field('product-search', with: '')
    expect(page.evaluate_script("document.activeElement && document.activeElement.id")).to eq('product-search')

    # Se teclea el siguiente SKU sin borrar nada a mano.
    fill_in 'product-search', with: product_b.product_sku
    click_button 'Buscar'
    fill_in "quantity-#{product_b.id}", with: '3'
    click_button "add-#{product_b.id}"

    expect(page).to have_css("li[data-batch-product-id='#{product_a.id}']")
    expect(page).to have_css("li[data-batch-product-id='#{product_b.id}']")
    expect(page).to have_css('#batch-products', text: '2 producto(s)')
    expect(page).to have_css('#batch-units', text: '8 pieza(s)')
  end

  it 'keeps what was typed when the add fails, so it can be corrected' do
    visit admin_inventory_unlocated_path
    choose_shelf

    fill_in 'product-search', with: product_a.product_sku
    click_button 'Buscar'
    expect(page).to have_css("tr[data-product-id='#{product_a.id}']")
    # Se relaja el min del input para poder ejercitar la validación del SERVIDOR.
    page.execute_script("document.getElementById('quantity-#{product_a.id}').removeAttribute('min')")
    fill_in "quantity-#{product_a.id}", with: '0'
    click_button "add-#{product_a.id}"

    expect(page).to have_content('mayor a cero')
    # El término sigue ahí y el resultado también: sólo hay que corregir la cantidad.
    expect(page).to have_field('product-search', with: product_a.product_sku)
    expect(page).to have_css("tr[data-product-id='#{product_a.id}']")
    expect(page).to have_css('#batch-empty')

    fill_in "quantity-#{product_a.id}", with: '4'
    click_button "add-#{product_a.id}"
    expect(page).to have_css('#batch-units', text: '4 pieza(s)')
  end
end
