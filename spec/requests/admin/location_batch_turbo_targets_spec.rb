# frozen_string_literal: true

require 'rails_helper'

# Cada acción debe tocar sólo su parte de la pantalla. Lo que se vigila aquí no
# es que Turbo "funcione", sino que no se cuele en el stream un panel que no le
# toca: repintar los resultados al agregar borraría el término y el scroll, y
# repintar el resumen del estante haría creer que la mercancía ya se movió.
RSpec.describe 'Admin location batch Turbo targets', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location) }
  let!(:shelf) { create(:inventory_location, parent: warehouse) }
  let(:product) { create(:product, skip_seed_inventory: true, product_name: 'Skyline GT-R', product_sku: 'TOM-123') }

  # Piezas ya guardadas en el estante: son las que debe contar el resumen.
  let!(:already_there) { create(:product, skip_seed_inventory: true, product_name: 'Supra Vieja', product_sku: 'TOM-999') }

  def turbo_headers = { 'Accept' => 'text/vnd.turbo-stream.html' }

  def stock(product, count, location: nil, status: :available)
    Array.new(count) { create(:inventory, product: product, status: status, inventory_location: location) }
  end

  before do
    sign_in admin
    stock(product, 6)
    stock(already_there, 4, location: shelf)
  end

  # full_path lleva " > ", que en el HTML sale escapado.
  def shelf_path_html = CGI.escapeHTML(shelf.full_path)

  def select_location(id = shelf.id)
    post admin_location_assignment_batch_location_path, params: { location_id: id }, headers: turbo_headers
  end

  def add_line(quantity = 2, term: 'TOM-123')
    post admin_location_assignment_batch_lines_path,
         params: { product_id: product.id, quantity: quantity, q: term }, headers: turbo_headers
  end

  describe 'POST location (cambiar de estante)' do
    it 'repinta ubicación, resumen, resultados y lote' do
      select_location

      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('selected-location-panel')
      expect(response.body).to include('location-current-inventory')
      expect(response.body).to include('product-search-results')
      expect(response.body).to include('location-batch-panel')
    end

    it 'trae ya contado lo que hay guardado en ese estante' do
      select_location

      expect(response.body).to include('Supra Vieja')
      expect(response.body).to include('4 pieza(s)')
    end
  end

  describe 'POST lines (agregar al lote)' do
    before { select_location }

    it 'repinta el lote y repone la cantidad de la fila agregada' do
      add_line(2)

      expect(response.body).to include('location-batch-panel')
      expect(response.body).to include("quantity-#{product.id}")
      expect(response.body).to include('2 pieza(s)')
    end

    it 'NO repinta los resultados de la búsqueda' do
      add_line(2)

      expect(response.body).not_to include('product-search-results')
      expect(response.body).not_to include('search-results-table')
    end

    # Lo que está en el lote todavía no se ha asignado: el estante no cambió.
    it 'NO repinta el resumen de la ubicación' do
      add_line(2)

      expect(response.body).not_to include('location-current-inventory')
    end

    it 'no toca nada cuando la cantidad es inválida' do
      add_line(0)

      expect(response.body).not_to include('location-batch-panel')
      expect(response.body).not_to include('product-search-results')
      expect(response.body).not_to include('location-current-inventory')
      expect(response.body).to include('mayor a cero')
    end
  end

  describe 'editar, quitar y vaciar' do
    before do
      select_location
      add_line(3)
    end

    def expect_only_the_batch
      expect(response.body).to include('location-batch-panel')
      expect(response.body).not_to include('product-search-results')
      expect(response.body).not_to include('location-current-inventory')
      expect(response.body).not_to include('selected-location-panel')
    end

    it 'editar la cantidad toca sólo el lote' do
      patch admin_location_assignment_batch_line_path(product_id: product.id),
            params: { quantity: 5 }, headers: turbo_headers

      expect_only_the_batch
      expect(response.body).to include('5 pieza(s)')
    end

    it 'quitar una línea toca sólo el lote' do
      delete admin_location_assignment_batch_remove_line_path(product_id: product.id), headers: turbo_headers

      expect_only_the_batch
      expect(response.body).to include('batch-empty')
    end

    it 'vaciar el lote toca sólo el lote y conserva el estante' do
      delete admin_location_assignment_batch_clear_path, headers: turbo_headers

      expect_only_the_batch
      expect(response.body).to include('batch-empty')

      get admin_inventory_unlocated_path
      expect(response.body).to include(shelf_path_html)
    end
  end

  # Aquí SÍ cambió el inventario real, así que el resumen tiene que reflejarlo.
  describe 'POST confirm' do
    before do
      select_location
      add_line(2)
    end

    it 'refresca el resumen de la ubicación con lo recién asignado' do
      post admin_location_assignment_batch_confirm_path

      follow_redirect!
      expect(response.body).to include('location-current-inventory')
      # 4 que ya estaban + 2 recién asignadas.
      expect(response.body).to include('6 pieza(s)')
      expect(response.body).to include('Skyline GT-R')
    end

    it 'deja el estante seleccionado y el lote vacío' do
      post admin_location_assignment_batch_confirm_path

      follow_redirect!
      expect(response.body).to include(shelf_path_html)
      expect(response.body).to include('batch-empty')
    end
  end

  # Ya no hay tope artificial de productos: el lote vive en la base, no en la
  # cookie de sesión, así que el único límite es el inventario real.
  describe 'sin tope artificial de líneas' do
    before { select_location }

    it 'conserva 50 y 100 productos distintos sin CookieOverflow, truncamiento ni pérdida' do
      100.times do |i|
        product = create(:product, skip_seed_inventory: true, product_name: "Masivo #{i}")
        stock(product, 1)
        post admin_location_assignment_batch_lines_path,
             params: { product_id: product.id, quantity: 1, q: 'Masivo' }, headers: turbo_headers
        expect(response).to have_http_status(:ok)
        expect(LocationAssignmentDraft.last.lines.count).to eq(50) if i == 49
      end

      draft = LocationAssignmentDraft.last
      expect(draft.lines.count).to eq(100)
      expect(draft.total_units).to eq(100)
    end

    it 'sí deja sumar más piezas a un producto que ya está en el lote' do
      add_line(1)
      add_line(2)

      expect(response.body).to include('3 pieza(s)')
    end
  end
end
