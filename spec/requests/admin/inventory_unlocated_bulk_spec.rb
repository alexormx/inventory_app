# frozen_string_literal: true

require 'rails_helper'

# La pantalla que usa el almacén: producto + cantidad + ubicación.
# El operador nunca escribe un Inventory ID.
RSpec.describe 'Admin unlocated bulk location assignment', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:product) { create(:product, skip_seed_inventory: true, product_name: 'Tomica Skyline', product_sku: 'TOM-123') }
  let(:warehouse) { create(:inventory_location) }
  let!(:shelf) { create(:inventory_location, parent: warehouse) }

  def unlocated(status: :available, prod: nil)
    create(:inventory, product: prod || product, status: status, inventory_location: nil)
  end

  # La pantalla pasó a ser por UBICACIÓN: primero se elige el estante y luego se
  # va armando el lote. El detalle producto-a-producto de la página vive ahora en
  # spec/requests/admin/location_assignment_batch_spec.rb.
  describe 'GET /admin/inventory/unlocated' do
    before { sign_in admin }

    it 'leads with the location selector' do
      3.times { unlocated }

      get admin_inventory_unlocated_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Ubicar inventario')
      expect(response.body).to include('batch-location-id')
    end

    it 'never asks the operator for Inventory ids' do
      2.times { unlocated }

      get admin_inventory_unlocated_path, params: { q: 'TOM-123' }

      expect(response.body).not_to include('inventory_ids[]')
      expect(response.body).to include("quantity-#{product.id}")
    end

    it 'separates assignable stock from pre_reserved still in transit' do
      2.times { unlocated(status: :available) }
      unlocated(status: :reserved)
      unlocated(status: :pre_reserved)

      get admin_inventory_unlocated_path, params: { q: 'TOM-123' }

      expect(response.body).to include('data-assignable="3"')
      expect(response.body).to include('Pre apartado / en tránsito')
    end

    it 'filters by product name or sku' do
      unlocated
      other = create(:product, skip_seed_inventory: true, product_name: 'Hot Wheels Otro', product_sku: 'HW-9')
      unlocated(prod: other)

      get admin_inventory_unlocated_path, params: { q: 'TOM-123' }

      expect(response.body).to include('Tomica Skyline')
      expect(response.body).not_to include('Hot Wheels Otro')
    end
  end

  describe 'POST /admin/inventory/bulk_assign_location' do
    before { sign_in admin }

    it 'assigns the requested quantity without the caller naming any Inventory id' do
      10.times { unlocated }

      expect do
        post admin_inventory_bulk_assign_location_path,
             params: { product_id: product.id, quantity: 4, inventory_location_id: shelf.id }
      end.to change { product.inventories.where(inventory_location_id: shelf.id).count }.by(4)

      expect(response).to redirect_to(admin_inventory_unlocated_path(q: nil, page: nil))
      follow_redirect!
      expect(flash[:notice] || response.body).to include('4 unidad(es)')
    end

    it 'refuses the whole request when there is not enough stock' do
      3.times { unlocated }

      post admin_inventory_bulk_assign_location_path,
           params: { product_id: product.id, quantity: 10, inventory_location_id: shelf.id }

      expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
      expect(flash[:alert]).to include('10')
      expect(flash[:alert]).to include('3')
      expect(flash[:alert]).to include('No se asignó ninguna')
    end

    it 'rejects a non-leaf location without touching inventory' do
      2.times { unlocated }

      post admin_inventory_bulk_assign_location_path,
           params: { product_id: product.id, quantity: 1, inventory_location_id: warehouse.id }

      expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
      expect(flash[:alert]).to include('final')
    end

    it 'rejects an invalid quantity without touching inventory' do
      2.times { unlocated }

      post admin_inventory_bulk_assign_location_path,
           params: { product_id: product.id, quantity: 0, inventory_location_id: shelf.id }

      expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
      expect(flash[:alert]).to be_present
    end

    it 'never selects pre_reserved stock' do
      pre = unlocated(status: :pre_reserved)
      unlocated(status: :available)

      post admin_inventory_bulk_assign_location_path,
           params: { product_id: product.id, quantity: 1, inventory_location_id: shelf.id }

      expect(pre.reload.inventory_location_id).to be_nil
    end
  end

  describe 'authorization' do
    it 'sends anonymous visitors to the login' do
      post admin_inventory_bulk_assign_location_path,
           params: { product_id: product.id, quantity: 1, inventory_location_id: shelf.id }

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'denies a signed-in non-admin' do
      sign_in create(:user, role: :customer)
      unlocated

      post admin_inventory_bulk_assign_location_path,
           params: { product_id: product.id, quantity: 1, inventory_location_id: shelf.id }

      expect(response).to redirect_to(root_path)
      expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
    end
  end
end
