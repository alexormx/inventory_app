# frozen_string_literal: true

require 'rails_helper'

Selenium::WebDriver.logger.level = :warn

# End-to-end flows intentionally verify the complete UI state and persisted result.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe 'Admin physical inventory verification', :js, type: :system do
  let(:admin) { create(:user, :admin, name: 'Verificador físico') }

  before { sign_in admin }

  def find_inventory(inventory)
    visit admin_inventory_verifications_path
    select 'Inventory ID', from: 'search_by'
    fill_in 'q', with: inventory.id
    click_button 'Buscar unidad'
    click_link "Verificar ##{inventory.id}"
    expect(page).to have_current_path(admin_inventory_verification_path(inventory))
    expect(page).to have_css('#found_verification_expected_snapshot_updated_at', visible: :hidden)
  end

  def accept_verification(button_label, inventory)
    click_button button_label
    expect(page).to have_css('#global-confirm-modal.show[aria-hidden="false"]', visible: true)

    within('#global-confirm-modal.show[aria-hidden="false"]') do
      expect(page).to have_content("Inventory ##{inventory.id}")
      click_button button_label
    end
  end

  def cancel_verification(button_label, inventory)
    click_button button_label
    expect(page).to have_css('#global-confirm-modal.show[aria-hidden="false"]', visible: true)

    within('#global-confirm-modal.show[aria-hidden="false"]') do
      expect(page).to have_content("Inventory ##{inventory.id}")
      click_button 'Cancelar'
    end

    expect(page).to have_no_css('#global-confirm-modal.show', visible: true)
  end

  it 'verifies an exact available unit as found and shows the audit result' do
    inventory = create(:inventory, status: :available, inventory_location: nil)
    location = create(:inventory_location, :warehouse, name: 'Anaquel sistema')

    find_inventory(inventory)
    find('#found_verification_location_id').find("option[value='#{location.id}']").select_option
    expect do
      accept_verification('Confirmar encontrado', inventory)
      expect(page).to have_content(/Verificación registrada/i)
    end.to change { InventoryEvent.where(event_type: 'physical_inventory_verification').count }.by(1)

    expect(page).to have_content("Inventory ##{inventory.id}")
    expect(page).to have_content('Encontrado')
    expect(page).to have_content('Verificador físico')
    expect(inventory.reload.inventory_location).to eq(location)
  end

  it 'previews and confirms an exact missing unit as lost' do
    inventory = create(:inventory, status: :available, inventory_location: nil)

    find_inventory(inventory)

    within('[data-verification-result="missing"]') do
      expect(page).to have_content('Actual')
      expect(page).to have_content('Disponible / Sin ubicación')
      expect(page).to have_content('Nuevo estado')
      expect(page).to have_content('Perdido')
    end
    accept_verification('Confirmar faltante', inventory)

    expect(page).to have_content(/Verificación registrada/i)
    expect(page).to have_content('Faltante')
    expect(inventory.reload).to be_lost
  end

  it 'does not mutate inventory when the Admin cancels confirmation' do
    inventory = create(:inventory, status: :available, inventory_location: nil)
    find_inventory(inventory)

    expect do
      cancel_verification('Confirmar faltante', inventory)
    end.not_to(change { InventoryEvent.where(event_type: 'physical_inventory_verification').count })

    expect(inventory.reload).to be_available
    expect(inventory.inventory_location_id).to be_nil
  end

  it 'only offers Found for reserved inventory and warns about reconciliation' do
    inventory = create(:inventory, status: :reserved, inventory_location: nil)

    find_inventory(inventory)

    expect(page).to have_button('Confirmar encontrado')
    expect(page).to have_no_button('Confirmar dañado')
    expect(page).to have_no_button('Confirmar faltante')
    expect(page).to have_content('requiere conciliación a nivel de orden')
  end

  it 'shows a conflict and does not overwrite a stale unit' do
    inventory = create(:inventory, status: :available, inventory_location: nil)
    find_inventory(inventory)
    inventory.update_column(:updated_at, inventory.reload.updated_at + 1.second)

    expect do
      accept_verification('Confirmar faltante', inventory)
      expect(page).to have_content('El inventario cambió')
    end.not_to(change { InventoryEvent.where(event_type: 'physical_inventory_verification').count })

    expect(page).to have_content('No se realizó ningún cambio')
    expect(page).to have_link('Revisar el estado actual')
    expect(inventory.reload).to be_available
  end

  it 'renders an invalid-snapshot 422 in the real browser without mutation' do
    inventory = create(:inventory, status: :available, inventory_location: nil)
    find_inventory(inventory)
    timestamp_input = find(
      '#missing_verification_expected_snapshot_updated_at',
      visible: :all
    )
    page.execute_script('arguments[0].remove()', timestamp_input.native)

    expect do
      accept_verification('Confirmar faltante', inventory)
      expect(page).to have_content('No fue posible validar el estado cargado')
    end.not_to(change { InventoryEvent.where(event_type: 'physical_inventory_verification').count })

    expect(page).to have_content('No se realizó ningún cambio')
    expect(inventory.reload).to be_available
  end

  it 'keeps the found flow usable at a mobile viewport' do
    inventory = create(:inventory, status: :available, inventory_location: nil)
    location = create(:inventory_location, :warehouse, name: 'Ubicación móvil')
    page.current_window.resize_to(390, 844)

    visit admin_inventory_verification_path(inventory)

    expect(page).to have_css('[data-verification-result="found"]', visible: true)
    expect(page).to have_button('Confirmar encontrado', visible: true)
    overflow = page.evaluate_script('document.documentElement.scrollWidth > document.documentElement.clientWidth + 1')
    expect(overflow).to be(false)

    find('#found_verification_location_id').find("option[value='#{location.id}']").select_option
    accept_verification('Confirmar encontrado', inventory)

    expect(page).to have_content(/Verificación registrada/i)
    expect(inventory.reload.inventory_location).to eq(location)
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
