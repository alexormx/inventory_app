# frozen_string_literal: true

require 'rails_helper'

# El recorrido completo tal cual se trabaja en bodega: pararse frente a un
# estante, ver qué hay YA guardado ahí, ir juntando lo que traes en la mano,
# corregir, revisar y confirmar una sola vez.
#
# Lo que se vigila en cada paso es la frontera entre las dos listas: lo que ya
# está guardado ("Actualmente en esta ubicación") no puede moverse porque metas
# algo al lote. Sólo se mueve al confirmar.
RSpec.describe 'Admin works a whole location through Turbo', :js, type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let!(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }

  let(:existing_a) { create(:product, skip_seed_inventory: true, product_name: 'Skyline Guardada', product_sku: 'OLD-111') }
  let(:existing_b) { create(:product, skip_seed_inventory: true, product_name: 'Supra Guardada', product_sku: 'OLD-222') }
  let(:new_a) { create(:product, skip_seed_inventory: true, product_name: 'Skyline Nueva', product_sku: 'NEW-111') }
  let(:new_b) { create(:product, skip_seed_inventory: true, product_name: 'Skyline Turbo', product_sku: 'NEW-222') }
  let(:new_c) { create(:product, skip_seed_inventory: true, product_name: 'Skyline Extra', product_sku: 'NEW-333') }

  def stock(product, count, location: nil)
    Array.new(count) { create(:inventory, product: product, status: :available, inventory_location: location) }
  end

  def choose_shelf
    select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: 'batch-location-id'
    click_button 'Seleccionar'
    expect(page).to have_css('#selected-location', text: 'Estante B03')
  end

  # Marca la ventana para poder demostrar que Turbo no recargó la página: si
  # hubiera navegación completa, el marcador desaparece.
  def mark_window
    page.execute_script("window.__noReload = 'kept'")
  end

  def expect_no_reload
    expect(page.evaluate_script('window.__noReload')).to eq('kept')
  end

  def add_product(product, quantity)
    fill_in "quantity-#{product.id}", with: quantity.to_s
    click_button "add-#{product.id}"
  end

  def current_location_total
    find('#current-location-units').text
  end

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
    stock(existing_a, 4, location: shelf)
    stock(existing_b, 2, location: shelf)
    stock(new_a, 10)
    stock(new_b, 8)
    stock(new_c, 6)
  end

  after { Warden.test_reset! }

  it 'shows what is already stored, batches the rest and only commits on confirm' do
    visit admin_inventory_unlocated_path
    choose_shelf

    # Lo que YA está en el estante, antes de tocar nada.
    expect(page).to have_css('#current-location-units', text: '6 pieza(s)')
    expect(page).to have_css('#current-location-products', text: '2 producto(s)')
    expect(page).to have_css("tr[data-current-product-id='#{existing_a.id}'][data-current-quantity='4']")
    expect(page).to have_css("tr[data-current-product-id='#{existing_b.id}'][data-current-quantity='2']")

    fill_in 'product-search', with: 'Skyline'
    click_button 'Buscar'
    expect(page).to have_css('#search-results-table tr[data-product-id]', count: 3)

    mark_window
    add_product(new_a, 3)

    # Turbo: el lote se mueve, la búsqueda no.
    expect(page).to have_css('#batch-units', text: '3 pieza(s)')
    expect_no_reload
    expect(page).to have_field('product-search', with: 'Skyline')
    expect(page).to have_css('#search-results-table tr[data-product-id]', count: 3)
    # Y sobre todo: el estante sigue con lo mismo que tenía.
    expect(current_location_total).to eq('6 pieza(s)')

    add_product(new_b, 2)
    expect(page).to have_css('#batch-products', text: '2 producto(s)')
    expect(page).to have_css('#batch-units', text: '5 pieza(s)')
    expect(current_location_total).to eq('6 pieza(s)')

    # Corregir la cantidad ya dentro del lote.
    fill_in "batch-qty-#{new_a.id}", with: '4'
    click_button "batch-update-#{new_a.id}"
    expect(page).to have_css('#batch-units', text: '6 pieza(s)')
    expect_no_reload
    expect(page).to have_css('#search-results-table tr[data-product-id]', count: 3)
    expect(current_location_total).to eq('6 pieza(s)')

    # Quitar una línea.
    click_button "batch-remove-#{new_b.id}"
    expect(page).to have_css('#batch-units', text: '4 pieza(s)')
    expect(page).to have_no_css("li[data-batch-product-id='#{new_b.id}']")
    expect_no_reload
    expect(current_location_total).to eq('6 pieza(s)')

    # Un tercer producto antes de revisar.
    add_product(new_c, 2)
    expect(page).to have_css('#batch-products', text: '2 producto(s)')
    expect(page).to have_css('#batch-units', text: '6 pieza(s)')

    # Nada ha tocado la base todavía.
    expect(Inventory.where(inventory_location_id: shelf.id).count).to eq(6)

    # Revisar y volver: el contexto se restaura.
    click_link 'Revisar asignación'
    expect(page).to have_css('#review-location', text: 'Estante B03')
    expect(page).to have_css('#review-total', text: '6 piezas')

    click_link 'Regresar'
    expect(page).to have_css('#batch-units', text: '6 pieza(s)')
    expect(page).to have_css('#selected-location', text: 'Estante B03')
    expect(current_location_total).to eq('6 pieza(s)')

    click_link 'Revisar asignación'
    click_button(id: 'confirm-batch')

    # Ahora sí: la mercancía se movió y el resumen lo refleja.
    expect(page).to have_content('6 unidades fueron asignadas')
    expect(page).to have_css('#batch-empty')
    expect(page).to have_css('#selected-location', text: 'Estante B03')
    expect(page).to have_css('#current-location-units', text: '12 pieza(s)')
    expect(page).to have_css("tr[data-current-product-id='#{new_a.id}'][data-current-quantity='4']")
    expect(page).to have_css("tr[data-current-product-id='#{new_c.id}'][data-current-quantity='2']")

    # Y por debajo: FIFO, ubicación y auditoría.
    expect(new_a.inventories.where(inventory_location_id: shelf.id).count).to eq(4)
    expect(new_c.inventories.where(inventory_location_id: shelf.id).count).to eq(2)
    expect(new_b.inventories.where(inventory_location_id: shelf.id)).to be_empty

    assigned = new_a.inventories.where(inventory_location_id: shelf.id).order(:created_at, :id)
    oldest = new_a.inventories.order(:created_at, :id).limit(4)
    expect(assigned.map(&:id)).to match_array(oldest.map(&:id))

    events = InventoryEvent.where(event_type: 'physical_inventory_verification')
    expect(events.count).to eq(6)
    batch_ids = events.map { |e| e['metadata']['assignment_batch_id'] }.uniq
    expect(batch_ids.size).to eq(1)
    expect(batch_ids.first).to be_present
  end

  it 'keeps the stored summary untouched when the confirmation fails' do
    visit admin_inventory_unlocated_path
    choose_shelf

    fill_in 'product-search', with: 'Skyline'
    click_button 'Buscar'
    add_product(new_a, 3)

    click_link 'Revisar asignación'

    # Otro operador se lleva casi todo justo antes de confirmar.
    Inventories::LocationAssignment.fifo_scope(new_a.id).limit(8)
                                   .each { |i| i.update!(inventory_location: shelf) }

    click_button(id: 'confirm-batch')

    expect(page).to have_content('No se realizó ninguna asignación')

    # El aviso de error no se auto-cierra a propósito (#128), así que tapa lo que
    # tenga debajo hasta que el operador lo cierra. Cerrarlo es parte del flujo.
    find('#flash-stack .alert-danger .btn-close').click
    expect(page).to have_no_css('#flash-stack .alert-danger')

    click_link 'Regresar'

    # El lote sigue ahí para poder corregirlo, y el estante no inventó piezas.
    expect(page).to have_css('#batch-units', text: '3 pieza(s)')
    expect(page).to have_css('#selected-location', text: 'Estante B03')
  end
end
