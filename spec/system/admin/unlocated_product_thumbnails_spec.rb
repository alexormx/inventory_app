# frozen_string_literal: true

require 'rails_helper'

# Una miniatura de referencia por producto, para reconocer la pieza de un vistazo
# sin leer el SKU. Misma fuente de imagen en búsqueda, lote, revisión y en el
# resumen de lo que ya está guardado en la ubicación.
RSpec.describe 'Unlocated: product thumbnails', :js, type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let!(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }
  let(:image_path) { Rails.root.join('spec/fixtures/files/test1.png') }

  let!(:with_image) { create(:product, skip_seed_inventory: true, product_name: 'Con Imagen', product_sku: 'IMG-1') }
  let!(:without_image) { create(:product, skip_seed_inventory: true, product_name: 'Sin Imagen', product_sku: 'IMG-0') }

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
    with_image.product_images.attach(io: File.open(image_path), filename: 'test1.png', content_type: 'image/png')
    # La factory adjunta imagen por defecto; aquí interesa el caso sin ninguna.
    without_image.product_images.purge
    [with_image, without_image].each do |p|
      4.times { create(:inventory, product: p, status: :available, inventory_location: nil) }
    end
  end

  after { Warden.test_reset! }

  def choose_shelf
    select "#{shelf.path_cache.presence || shelf.name} (#{shelf.code})", from: 'batch-location-id'
    click_button 'Seleccionar'
    expect(page).to have_css('#selected-location')
  end

  it 'shows a real thumbnail for a product that has an image' do
    visit admin_inventory_unlocated_path
    choose_shelf
    fill_in 'product-search', with: 'IMG-1'
    click_button 'Buscar'

    expect(page).to have_css("tr[data-product-id='#{with_image.id}'] img")
  end

  it 'shows a safe placeholder, not a broken image, when there is none' do
    visit admin_inventory_unlocated_path
    choose_shelf
    fill_in 'product-search', with: 'IMG-0'
    click_button 'Buscar'

    row = "tr[data-product-id='#{without_image.id}']"
    expect(page).to have_css(row)
    expect(page).to have_no_css("#{row} img")
    expect(page).to have_css("#{row} i.fa-image")
  end

  it 'carries the thumbnail into the batch and the review screen' do
    visit admin_inventory_unlocated_path
    choose_shelf
    fill_in 'product-search', with: 'IMG-1'
    click_button 'Buscar'
    fill_in "quantity-#{with_image.id}", with: '2'
    click_button "add-#{with_image.id}"

    expect(page).to have_css("li[data-batch-product-id='#{with_image.id}'] img")

    click_link 'Revisar asignación'
    expect(page).to have_css("#review-lines tr[data-review-product-id='#{with_image.id}'] img")
  end

  it 'renders a mixed result set without blowing up' do
    visit admin_inventory_unlocated_path
    choose_shelf
    fill_in 'product-search', with: 'IMG'
    click_button 'Buscar'

    expect(page).to have_css('#search-results-table tr[data-product-id]', count: 2)
    expect(page).to have_css("tr[data-product-id='#{with_image.id}'] img")
    expect(page).to have_css("tr[data-product-id='#{without_image.id}'] i.fa-image")
  end

  it 'keeps the action column reachable at a tablet width' do
    page.current_window.resize_to(820, 1000)
    visit admin_inventory_unlocated_path
    choose_shelf
    fill_in 'product-search', with: 'IMG'
    click_button 'Buscar'

    expect(page).to have_css("#add-#{with_image.id}")
    overflow = page.evaluate_script('document.documentElement.scrollWidth > document.documentElement.clientWidth + 1')
    expect(overflow).to be(false)

    fill_in "quantity-#{with_image.id}", with: '1'
    click_button "add-#{with_image.id}"
    expect(page).to have_css("li[data-batch-product-id='#{with_image.id}']")
  end
  # El resumen del estante usa el MISMO partial: si alguien lo duplicara, este
  # ejemplo seguiría verde pero el de abajo —el del fallback— no.
  context 'en el resumen de la ubicación' do
    let!(:stored_with_image) do
      create(:product, skip_seed_inventory: true, product_name: 'Guardada Con Imagen', product_sku: 'ST-1')
    end
    let!(:stored_without_image) do
      create(:product, skip_seed_inventory: true, product_name: 'Guardada Sin Imagen', product_sku: 'ST-0')
    end

    before do
      stored_with_image.product_images.attach(
        io: File.open(image_path), filename: 'test1.png', content_type: 'image/png'
      )
      stored_without_image.product_images.purge
      create(:inventory, product: stored_with_image, status: :available, inventory_location: shelf)
      create(:inventory, product: stored_without_image, status: :available, inventory_location: shelf)
    end

    it 'pinta la miniatura de lo que ya está en el estante' do
      visit admin_inventory_unlocated_path
      choose_shelf

      expect(page).to have_css("tr[data-current-product-id='#{stored_with_image.id}'] img")
    end

    it 'cae al icono de Font Awesome cuando el producto guardado no tiene imagen' do
      visit admin_inventory_unlocated_path
      choose_shelf

      expect(page).to have_css("tr[data-current-product-id='#{stored_without_image.id}'] i.fa-image")
      expect(page).to have_no_css("tr[data-current-product-id='#{stored_without_image.id}'] img")
    end
  end
end
