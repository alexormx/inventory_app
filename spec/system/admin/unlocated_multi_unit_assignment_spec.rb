# frozen_string_literal: true

require 'rails_helper'

# Recorrido real del admin: entrar por /admin/inventory/unlocated, marcar
# unidades concretas, revisarlas y confirmar. Lo que se protege es que la
# ubicación sólo llega a las piezas que el admin marcó viéndolas.
RSpec.describe 'Admin assigns locations to several unlocated units', :js, type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:product) { create(:product, skip_seed_inventory: true, product_name: 'Tomica Skyline Unlocated') }
  let(:warehouse) { create(:inventory_location, name: 'Bodega Central') }
  let!(:shelf) { create(:inventory_location, name: 'Estante A1', parent: warehouse) }

  let!(:first_unit)  { create(:inventory, product: product, status: :available, inventory_location: nil) }
  let!(:second_unit) { create(:inventory, product: product, status: :available, inventory_location: nil) }
  let!(:untouched_unit) { create(:inventory, product: product, status: :available, inventory_location: nil) }

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  it 'assigns only the selected units and audits each one' do
    visit admin_inventory_unlocated_path

    expect(page).to have_current_path(admin_inventory_verifications_path, ignore_query: true)
    expect(page).to have_css('#bulk-assign-form')

    check "inventory-select-#{first_unit.id}"
    check "inventory-select-#{second_unit.id}"
    expect(page).to have_css('#bulk-selected-count', text: '2 seleccionadas')

    click_button 'Asignar ubicación a la selección'

    # Revisión: las unidades exactas quedan a la vista antes de escribir nada.
    expect(page).to have_css('#bulk-review-table tr[data-inventory-id]', count: 2)
    expect(page).to have_css("#bulk-review-table tr[data-inventory-id='#{first_unit.id}']")
    expect(page).to have_css("#bulk-review-table tr[data-inventory-id='#{second_unit.id}']")
    expect(page).to have_no_css("#bulk-review-table tr[data-inventory-id='#{untouched_unit.id}']")
    expect(first_unit.reload.inventory_location_id).to be_nil

    select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: 'location_id'

    expect do
      click_button "Confirmar asignación de 2 unidad(es)"
      expect(page).to have_css('#bulk-count-assigned', text: '2')
    end.to change(InventoryEvent, :count).by(2)

    expect(first_unit.reload.inventory_location_id).to eq(shelf.id)
    expect(second_unit.reload.inventory_location_id).to eq(shelf.id)
    expect(untouched_unit.reload.inventory_location_id).to be_nil

    events = InventoryEvent.where(event_type: 'physical_inventory_verification')
    expect(events.pluck(:inventory_id)).to match_array([first_unit.id, second_unit.id])
  end

  it 'assigns the healthy unit and reports the one that changed underneath' do
    visit admin_inventory_unlocated_path

    check "inventory-select-#{first_unit.id}"
    check "inventory-select-#{second_unit.id}"
    click_button 'Asignar ubicación a la selección'

    expect(page).to have_css('#bulk-review-table tr[data-inventory-id]', count: 2)
    select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: 'location_id'

    # Otra persona toca la pieza entre la revisión y la confirmación.
    second_unit.update!(status: :damaged)

    click_button "Confirmar asignación de 2 unidad(es)"

    expect(page).to have_css('#bulk-count-assigned', text: '1')
    expect(page).to have_css("#bulk-failures-table tr[data-inventory-id='#{second_unit.id}']")

    expect(first_unit.reload.inventory_location_id).to eq(shelf.id)
    expect(second_unit.reload.inventory_location_id).to be_nil
  end
end
