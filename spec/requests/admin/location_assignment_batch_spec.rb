# frozen_string_literal: true

require 'rails_helper'

# El lote de ubicación: elegir estante, ir agregando productos, confirmar una vez.
RSpec.describe 'Admin location assignment batch', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location) }
  let!(:shelf) { create(:inventory_location, parent: warehouse) }
  let!(:other_shelf) { create(:inventory_location, parent: warehouse) }
  let(:product_a) { create(:product, skip_seed_inventory: true, product_name: 'Skyline GT-R', product_sku: 'TOM-123') }
  let(:product_b) { create(:product, skip_seed_inventory: true, product_name: 'Supra', product_sku: 'TOM-555') }

  def stock(product, count, status: :available)
    Array.new(count) { create(:inventory, product: product, status: status, inventory_location: nil) }
  end

  def select_location(id = shelf.id, **extra)
    post admin_location_assignment_batch_location_path, params: { location_id: id, **extra }
  end

  def add_line(product, quantity)
    post admin_location_assignment_batch_lines_path, params: { product_id: product.id, quantity: quantity }
  end

  before { sign_in admin }

  describe 'the page' do
    it 'leads with the location selector, not a per-product assign row' do
      stock(product_a, 3)

      get admin_inventory_unlocated_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Paso 1')
      expect(response.body).to include('batch-location-id')
      expect(response.body).to include('Paso 3')
      expect(response.body).not_to include('inventory_ids[]')
    end

    it 'does not list products until you search' do
      stock(product_a, 3)

      get admin_inventory_unlocated_path

      expect(response.body).not_to include('search-results-table')
    end

    it 'finds products by name and by SKU' do
      stock(product_a, 3); stock(product_b, 2)

      get admin_inventory_unlocated_path, params: { q: 'TOM-123' }
      expect(response.body).to include('Skyline GT-R')
      expect(response.body).not_to include('Supra')

      get admin_inventory_unlocated_path, params: { q: 'supra' }
      expect(response.body).to include('Supra')
    end

    it 'shows assignable apart from pre_reserved in transit' do
      stock(product_a, 2, status: :available)
      stock(product_a, 1, status: :reserved)
      stock(product_a, 1, status: :pre_reserved)

      get admin_inventory_unlocated_path, params: { q: 'TOM-123' }

      expect(response.body).to include('data-assignable="3"')
      expect(response.body).to include('Pre apartado / en tránsito')
    end
  end

  describe 'building the batch' do
    before { stock(product_a, 10); stock(product_b, 8) }

    it 'refuses to add anything before a location is chosen' do
      add_line(product_a, 3)

      follow_redirect!
      expect(response.body).to include('batch-empty')
      expect(flash[:alert]).to include('ubicación')
    end

    it 'accumulates several products under one location' do
      select_location
      add_line(product_a, 5)
      add_line(product_b, 3)

      get admin_inventory_unlocated_path
      expect(response.body).to include('Skyline GT-R')
      expect(response.body).to include('Supra')
      expect(response.body).to include('8 pieza(s)')
      expect(response.body).to include('2 producto(s)')
    end

    it 'combines the same product instead of duplicating the line' do
      select_location
      add_line(product_a, 3)
      add_line(product_a, 2)

      get admin_inventory_unlocated_path
      expect(response.body.scan("data-batch-product-id=\"#{product_a.id}\"").size).to eq(1)
      expect(response.body).to include('5 pieza(s)')
    end

    it 'edits a line quantity' do
      select_location
      add_line(product_a, 5)

      patch admin_location_assignment_batch_line_path(product_id: product_a.id), params: { quantity: 2 }

      get admin_inventory_unlocated_path
      expect(response.body).to include('2 pieza(s)')
    end

    it 'removes a line' do
      select_location
      add_line(product_a, 5)

      delete admin_location_assignment_batch_remove_line_path(product_id: product_a.id)

      get admin_inventory_unlocated_path
      expect(response.body).to include('batch-empty')
    end

    it 'clears the whole batch' do
      select_location
      add_line(product_a, 5); add_line(product_b, 2)

      delete admin_location_assignment_batch_clear_path

      get admin_inventory_unlocated_path
      expect(response.body).to include('batch-empty')
    end

    it 'rejects a non-positive quantity' do
      select_location
      add_line(product_a, 0)

      expect(flash[:alert]).to include('mayor a cero')
    end
  end

  describe 'changing location with a non-empty batch' do
    before { stock(product_a, 10) }

    it 'refuses silently mixing locations' do
      select_location
      add_line(product_a, 5)

      select_location(other_shelf.id)

      expect(flash[:alert]).to include('Ya tienes')
      get admin_inventory_unlocated_path
      expect(response.body).to include(ERB::Util.html_escape(shelf.full_path))
    end

    it 'changes location and empties the batch when confirmed' do
      select_location
      add_line(product_a, 5)

      select_location(other_shelf.id, confirm_change: '1')

      get admin_inventory_unlocated_path
      expect(response.body).to include(ERB::Util.html_escape(other_shelf.full_path))
      expect(response.body).to include('batch-empty')
    end
  end

  describe 'review and confirm' do
    before { stock(product_a, 10); stock(product_b, 8) }

    it 'shows the batch for review without writing anything' do
      select_location
      add_line(product_a, 5); add_line(product_b, 3)

      expect { get admin_location_assignment_batch_review_path }.not_to change(InventoryEvent, :count)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(ERB::Util.html_escape(shelf.full_path))
      expect(response.body).to include('8 piezas')
    end

    it 'assigns the entire batch on confirm and clears it' do
      select_location
      add_line(product_a, 5); add_line(product_b, 3)

      expect { post admin_location_assignment_batch_confirm_path }
        .to change(InventoryEvent, :count).by(8)

      expect(product_a.inventories.where(inventory_location_id: shelf.id).count).to eq(5)
      expect(product_b.inventories.where(inventory_location_id: shelf.id).count).to eq(3)
      expect(flash[:notice]).to include('8 unidades')
      expect(flash[:notice]).to include(shelf.full_path)

      get admin_inventory_unlocated_path
      expect(response.body).to include('batch-empty')
    end

    it 'writes nothing at all when one line falls short' do
      select_location
      add_line(product_a, 5)
      add_line(product_b, 3)
      # Otro operador se lleva piezas de B antes de confirmar.
      Inventories::LocationAssignment.fifo_scope(product_b.id).limit(6)
                                     .each { |i| i.update!(inventory_location: other_shelf) }

      expect { post admin_location_assignment_batch_confirm_path }.not_to change(InventoryEvent, :count)

      expect(product_a.inventories.where(inventory_location_id: shelf.id)).to be_empty
      expect(flash[:alert]).to include('No se realizó ninguna asignación')
      expect(flash[:alert]).to include('Supra')
    end

    it 'refuses to review an empty batch' do
      select_location
      get admin_location_assignment_batch_review_path

      expect(response).to redirect_to(admin_inventory_unlocated_path(q: nil))
    end
  end

  describe 'authorization' do
    it 'sends anonymous visitors to the login' do
      sign_out admin

      post admin_location_assignment_batch_confirm_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'denies a signed-in non-admin' do
      sign_out admin
      sign_in create(:user, role: :customer)
      post admin_location_assignment_batch_confirm_path
      expect(response).to redirect_to(root_path)
    end
  end

  # El trabajo es en cadena: SKU, agregar, siguiente SKU. Dejar el término
  # anterior obliga a borrarlo a mano cada vez.
  describe 'search field after adding' do
    before { stock(product_a, 10); stock(product_b, 8); select_location }

    it 'clears the search after a successful add' do
      post admin_location_assignment_batch_lines_path,
           params: { product_id: product_a.id, quantity: 3, q: 'TOM-123' }

      expect(response).to redirect_to(admin_inventory_unlocated_path)
      follow_redirect!
      expect(response.body).to include('value=""')
      expect(response.body).not_to include('search-results-table')
    end

    it 'keeps the search term and the typed quantity when the add fails' do
      post admin_location_assignment_batch_lines_path,
           params: { product_id: product_a.id, quantity: 0, q: 'TOM-123' }

      expect(response).to redirect_to(
        admin_inventory_unlocated_path(q: 'TOM-123', retry_product_id: product_a.id, retry_quantity: '0')
      )
      follow_redirect!
      expect(response.body).to include('TOM-123')
      expect(response.body).to include('search-results-table')
    end

    it 'lets the operator chain one SKU after another without clearing by hand' do
      post admin_location_assignment_batch_lines_path,
           params: { product_id: product_a.id, quantity: 3, q: 'TOM-123' }
      post admin_location_assignment_batch_lines_path,
           params: { product_id: product_b.id, quantity: 2, q: 'TOM-555' }

      get admin_inventory_unlocated_path
      expect(response.body).to include('Skyline GT-R')
      expect(response.body).to include('Supra')
      expect(response.body).to include('2 producto(s)')
      expect(response.body).to include('5 pieza(s)')
    end

    it 'keeps the location and the batch intact after clearing the search' do
      post admin_location_assignment_batch_lines_path,
           params: { product_id: product_a.id, quantity: 3, q: 'TOM-123' }

      get admin_inventory_unlocated_path
      expect(response.body).to include(ERB::Util.html_escape(shelf.full_path))
      expect(response.body).to include('3 pieza(s)')
    end
  end
end
