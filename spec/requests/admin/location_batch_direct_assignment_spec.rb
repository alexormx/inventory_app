# frozen_string_literal: true

require 'rails_helper'

# Las reglas que el operador no puede ver pero sí sufre: no pasarse del
# inventario por pulsar dos veces, que "todas las disponibles" signifique lo que
# hay ahora, y que asignar dos veces no duplique la mercancía.
RSpec.describe 'Admin location batch direct assignment', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location) }
  let!(:shelf) { create(:inventory_location, parent: warehouse) }
  let(:product) { create(:product, skip_seed_inventory: true, product_name: 'Skyline', product_sku: 'SKY-1') }
  let(:other) { create(:product, skip_seed_inventory: true, product_name: 'Supra', product_sku: 'SUP-1') }

  def turbo_headers = { 'Accept' => 'text/vnd.turbo-stream.html' }

  def stock(prod, count, location: nil, status: :available)
    Array.new(count) { create(:inventory, product: prod, status: status, inventory_location: location) }
  end

  def draft = LocationAssignmentDraft.find_by(user: admin)

  def add(prod, quantity, term: 'SKY')
    post admin_location_assignment_batch_lines_path,
         params: { product_id: prod.id, quantity: quantity, q: term }, headers: turbo_headers
  end

  def add_all(prod, term: 'SKY')
    post admin_location_assignment_batch_add_all_lines_path(product_id: prod.id),
         params: { q: term }, headers: turbo_headers
  end

  def assign_all(term: 'SKY')
    post admin_location_assignment_batch_assign_all_path, params: { q: term }, headers: turbo_headers
  end

  before do
    sign_in admin
    post admin_location_assignment_batch_location_path, params: { location_id: shelf.id }, headers: turbo_headers
  end

  describe 'no pasarse del inventario' do
    before { stock(product, 5) }

    it 'rechaza el segundo Agregar que se pasaría y dice cuánto cabe' do
      add(product, 3)
      expect(draft.pending_for(product.id)).to eq(3)

      add(product, 3)

      expect(draft.pending_for(product.id)).to eq(3)
      expect(response.body).to include('sólo puedes agregar 2 más')
    end

    it 'acepta exactamente lo que queda' do
      add(product, 3)
      add(product, 2)

      expect(draft.pending_for(product.id)).to eq(5)
    end

    it 'nunca deja el pendiente por encima de lo asignable', :aggregate_failures do
      10.times { add(product, 4) }

      expect(draft.pending_for(product.id)).to be <= 5
      expect(draft.pending_for(product.id)).to eq(4)
    end

    it 'no cuenta pre_reserved como asignable' do
      stock(product, 3, status: :pre_reserved)

      add(product, 8)

      expect(draft.pending_for(product.id)).to eq(0)
      expect(response.body).to include('sólo puedes agregar 5 más')
    end

    it 'sí cuenta reserved' do
      stock(product, 2, status: :reserved)

      add(product, 7)

      expect(draft.pending_for(product.id)).to eq(7)
    end
  end

  describe 'agregar todas las disponibles' do
    before { stock(product, 10) }

    it 'agrega el total cuando el lote está vacío' do
      add_all(product)

      expect(draft.pending_for(product.id)).to eq(10)
    end

    it 'resta lo que ya está en el lote' do
      add(product, 4)
      add_all(product)

      expect(draft.pending_for(product.id)).to eq(10)
    end

    it 'pulsarlo dos veces no agrega de más' do
      add_all(product)
      add_all(product)

      expect(draft.pending_for(product.id)).to eq(10)
      expect(response.body).to include('ya tienes en el lote todo el inventario')
    end
  end

  describe 'asignación directa' do
    before do
      stock(product, 5)
      stock(other, 3)
      add(product, 5)
      add(other, 2)
    end

    it 'asigna todo el lote y lo vacía, sin pasar por revisión' do
      expect { assign_all }.to change {
        Inventory.where(inventory_location_id: shelf.id).count
      }.from(0).to(7)

      expect(draft.reload).to be_empty
      expect(response.body).to include('location-current-inventory')
      expect(response.body).to include('location-batch-panel')
      expect(response.body).to include('product-search-results')
    end

    it 'un segundo envío no vuelve a asignar' do
      assign_all
      expect { assign_all }.not_to(change { Inventory.where(inventory_location_id: shelf.id).count })

      expect(response.body).to include('ya se había asignado')
    end

    it 'usa un solo UUID de lote para todos los eventos' do
      assign_all

      events = InventoryEvent.where(event_type: 'physical_inventory_verification')
      expect(events.count).to eq(7)
      expect(events.map { |e| e['metadata']['assignment_batch_id'] }.uniq.size).to eq(1)
    end

    it 'todo o nada: si una línea no alcanza no se asigna ninguna' do
      # Se van piezas del segundo producto después de armar el lote.
      other.inventories.where(inventory_location_id: nil).limit(2).destroy_all

      expect { assign_all }.not_to(change { Inventory.where(inventory_location_id: shelf.id).count })

      expect(draft.reload.total_units).to eq(7)
      expect(response.body).to include('No se realizó ninguna asignación')
    end

    it 'conserva el lote y no toca el resumen cuando falla' do
      other.inventories.where(inventory_location_id: nil).limit(2).destroy_all
      assign_all

      expect(draft.reload).not_to be_empty
      expect(response.body).not_to include('location-current-inventory')
    end
  end

  describe 'fallback HTML' do
    before do
      stock(product, 4)
      add(product, 4)
    end

    it 'asigna y vuelve a /unlocated, nunca a revisión' do
      post admin_location_assignment_batch_assign_all_path, params: { q: 'SKY' }

      expect(response).to redirect_to(admin_inventory_unlocated_path(q: 'SKY'))
      expect(Inventory.where(inventory_location_id: shelf.id).count).to eq(4)
    end
  end
end
