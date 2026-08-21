# frozen_string_literal: true

require 'rails_helper'

# Reporte real del almacén: se elige ubicación, se busca por NOMBRE, aparece el
# producto con inventario asignable... y "Agregar" no responde.
#
# La causa no era un botón deshabilitado: la cantidad venía vacía y es required,
# así que el navegador bloqueaba el envío y ponía su globo sobre la CELDA DE
# CANTIDAD, no sobre el botón. Desde la vista del operador, "Agregar" no hacía
# nada. Estos specs fijan el contrato de estado del botón.
RSpec.describe 'Unlocated: Agregar button state', :js, type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let!(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }

  let(:product) do
    create(:product, skip_seed_inventory: true,
                     product_name: 'Tomica Nissan Skyline', product_sku: 'TOM-123')
  end

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  def stock(prod, count, status: :available)
    Array.new(count) { create(:inventory, product: prod, status: status, inventory_location: nil) }
  end

  def choose_shelf
    select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: 'batch-location-id'
    click_button 'Seleccionar'
    expect(page).to have_css('#selected-location')
  end

  def search(term)
    fill_in 'product-search', with: term
    click_button 'Buscar'
  end

  # El caso exacto que reportó el usuario.
  it 'lets the operator add a product found by NAME, right away' do
    stock(product, 8)
    stock(product, 2, status: :reserved)

    visit admin_inventory_unlocated_path
    choose_shelf
    search 'Nissan Skyline'

    expect(page).to have_css("tr[data-product-id='#{product.id}'] [data-assignable='10']")

    # La cantidad viene lista y el formulario es válido: el botón responde al primer clic.
    expect(page).to have_field("quantity-#{product.id}", with: '1')
    expect(find("#add-#{product.id}")).not_to be_disabled
    expect(page.evaluate_script("document.getElementById('add-form-#{product.id}').checkValidity()")).to be(true)

    click_button "add-#{product.id}"

    expect(page).to have_css("li[data-batch-product-id='#{product.id}']")
    expect(page).to have_css('#batch-units', text: '1 pieza(s)')
    # El contexto de búsqueda se queda: se puede agregar otro SKU del mismo
    # resultado sin volver a teclear.
    expect(page).to have_field('product-search', with: 'Nissan Skyline')
    expect(page).to have_css('#selected-location')
  end

  it 'behaves identically when the product is found by SKU' do
    stock(product, 5)

    visit admin_inventory_unlocated_path
    choose_shelf
    search 'TOM-123'

    expect(page).to have_field("quantity-#{product.id}", with: '1')
    expect(find("#add-#{product.id}")).not_to be_disabled

    click_button "add-#{product.id}"
    expect(page).to have_css('#batch-units', text: '1 pieza(s)')
  end

  it 'accepts a quantity the operator types over the default' do
    stock(product, 9)

    visit admin_inventory_unlocated_path
    choose_shelf
    search 'TOM-123'

    fill_in "quantity-#{product.id}", with: '4'
    click_button "add-#{product.id}"

    expect(page).to have_css('#batch-units', text: '4 pieza(s)')
  end

  describe 'eligibility drives the button, and says so' do
    it 'is usable with available stock only' do
      stock(product, 3)
      visit admin_inventory_unlocated_path
      choose_shelf
      search 'TOM-123'

      expect(page).to have_css("tr[data-product-id='#{product.id}'] [data-assignable='3']")
      expect(find("#add-#{product.id}")).not_to be_disabled
    end

    it 'is usable with reserved stock only' do
      stock(product, 3, status: :reserved)
      visit admin_inventory_unlocated_path
      choose_shelf
      search 'TOM-123'

      expect(page).to have_css("tr[data-product-id='#{product.id}'] [data-assignable='3']")
      expect(find("#add-#{product.id}")).not_to be_disabled
    end

    it 'is disabled WITH a stated reason when only pre_reserved is left' do
      stock(product, 3, status: :pre_reserved)
      visit admin_inventory_unlocated_path
      choose_shelf
      search 'TOM-123'

      expect(page).to have_css("tr[data-product-id='#{product.id}'] [data-assignable='0']")
      expect(find("#add-#{product.id}", visible: :all)).to be_disabled
      expect(page).to have_css("#no-stock-#{product.id}", text: 'Sin inventario disponible para asignar')
    end
  end

  it 'explains why adding is blocked before a location is chosen' do
    stock(product, 5)

    visit admin_inventory_unlocated_path
    search 'TOM-123'

    expect(find("#add-#{product.id}", visible: :all)).to be_disabled
    expect(page).to have_css("#no-location-#{product.id}", text: 'Selecciona primero la ubicación destino')
  end

  # El max del input es sólo comodidad: quien decide es el servidor. Antes el
  # lote aceptaba cualquier número y el fallo aparecía hasta el final; ahora se
  # rechaza en el momento y se dice cuánto cabe.
  it 'rejects an over-request server-side and says how many fit' do
    stock(product, 2)

    visit admin_inventory_unlocated_path
    choose_shelf
    search 'TOM-123'
    expect(page).to have_css("tr[data-product-id='#{product.id}']")

    # Se relaja el max del input para ejercitar la validación del SERVIDOR.
    page.execute_script("document.getElementById('quantity-#{product.id}').removeAttribute('max')")
    fill_in "quantity-#{product.id}", with: '99'
    click_button "add-#{product.id}"

    expect(page).to have_content('sólo puedes agregar 2 más')
    expect(page).to have_css('#batch-units', text: '0 pieza(s)')
    expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
  end
end
