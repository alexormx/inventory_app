# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::Inventory location explorer', type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    sign_in admin
  end

  describe 'GET /admin/inventory/location_explorer' do
    it 'muestra piezas sin ubicación en modo unlocated' do
      product_unlocated = create(:product, skip_seed_inventory: true, product_name: 'Producto Sin Ubicación', product_sku: 'SKU-UNLOC')
      product_located = create(:product, skip_seed_inventory: true, product_name: 'Producto Ubicado', product_sku: 'SKU-LOC')
      location = create(:inventory_location, :warehouse)

      create(:inventory, product: product_unlocated, status: :available, inventory_location_id: nil, purchase_cost: 10)
      create(:inventory, product: product_unlocated, status: :pre_reserved, inventory_location_id: nil, purchase_cost: 10)
      create(:inventory, product: product_located, status: :available, inventory_location: location, purchase_cost: 10)

      get admin_inventory_location_explorer_path(mode: 'unlocated')

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Producto Sin Ubicación')
      expect(response.body).not_to include('Producto Ubicado')
      expect(response.body).to include('2 piezas')
    end

    it 'muestra piezas de la ubicación seleccionada en modo location' do
      location_a = create(:inventory_location, :warehouse, name: 'Bodega A')
      location_b = create(:inventory_location, :warehouse, name: 'Bodega B')

      product_a = create(:product, skip_seed_inventory: true, product_name: 'Producto A', product_sku: 'SKU-A')
      product_b = create(:product, skip_seed_inventory: true, product_name: 'Producto B', product_sku: 'SKU-B')

      create(:inventory, product: product_a, status: :reserved, inventory_location: location_a, purchase_cost: 15)
      create(:inventory, product: product_b, status: :available, inventory_location: location_b, purchase_cost: 20)

      get admin_inventory_location_explorer_path(mode: 'location', location_id: location_a.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Producto A')
      expect(response.body).not_to include('Producto B')
      expect(response.body).to include('Bodega A')
    end

    it 'no incluye estados que no requieren ubicación' do
      product_sold = create(:product, skip_seed_inventory: true, product_name: 'Producto Vendido', product_sku: 'SKU-SOLD')
      create(:inventory, product: product_sold, status: :sold, inventory_location_id: nil, purchase_cost: 30)

      get admin_inventory_location_explorer_path(mode: 'unlocated')

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('Producto Vendido')
    end

    it 'pide seleccionar ubicación cuando mode=location sin location_id' do
      get admin_inventory_location_explorer_path(mode: 'location')

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Selecciona una ubicación para ver resultados')
    end

    it 'permite revisar inventario no asignado por categoría' do
      product_a = create(:product, skip_seed_inventory: true, product_name: 'Tamiya A', product_sku: 'TAM-A', category: 'model_kits')
      product_b = create(:product, skip_seed_inventory: true, product_name: 'Tamiya B', product_sku: 'TAM-B', category: 'model_kits')
      product_c = create(:product, skip_seed_inventory: true, product_name: 'Funko C', product_sku: 'FUN-C', category: 'collectibles')

      create(:inventory, product: product_a, status: :available, inventory_location_id: nil, purchase_cost: 10)
      create(:inventory, product: product_b, status: :reserved, inventory_location_id: nil, purchase_cost: 10)
      create(:inventory, product: product_c, status: :pre_reserved, inventory_location_id: nil, purchase_cost: 10)

      get admin_inventory_location_explorer_path(mode: 'unlocated', view: 'categories', sort: 'count_desc')

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Tamiya A')
      expect(response.body).to include('Tamiya B')
      expect(response.body).to include('Funko C')
      expect(response.body).to include('Categoría')
      expect(response.body).to include('Por categoría (solo sin ubicación)')
    end

    it 'permite seleccionar una categoría específica para revisar' do
      product_a = create(:product, skip_seed_inventory: true, product_name: 'Tamiya A', product_sku: 'TAM-A', category: 'model_kits')
      product_b = create(:product, skip_seed_inventory: true, product_name: 'Funko B', product_sku: 'FUN-B', category: 'collectibles')

      create(:inventory, product: product_a, status: :available, inventory_location_id: nil, purchase_cost: 10)
      create(:inventory, product: product_b, status: :reserved, inventory_location_id: nil, purchase_cost: 10)

      get admin_inventory_location_explorer_path(mode: 'unlocated', view: 'categories', category: 'model_kits')

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Tamiya A')
      expect(response.body).not_to include('Funko B')
    end
  end

  # Corrección de negocio: en esta bodega las piezas NO se etiquetan una por
  # una, así que exigir Inventory IDs exactos era inoperable. Vuelve la acción
  # real —producto + cantidad + ubicación— pero sobre el servicio nuevo, con
  # bloqueo, validación de ubicación y todo-o-nada. Lo que NO vuelve es el
  # update_all a ciegas del código viejo.
  describe 'bulk assignment by product and quantity' do
    it 'serves the unlocated screen as the location-first batch page' do
      product = create(:product, skip_seed_inventory: true, product_name: 'Tomica Bulk')
      create(:inventory, product: product, status: :available, inventory_location: nil)

      get admin_inventory_unlocated_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Ubicar inventario')
      expect(response.body).to include('batch-location-id')
    end

    it 'assigns the requested quantity through the locked service' do
      product = create(:product, skip_seed_inventory: true)
      pieces = Array.new(3) do
        create(:inventory, product: product, status: :available, inventory_location: nil)
      end
      warehouse = create(:inventory_location, :warehouse)
      shelf = create(:inventory_location, parent: warehouse)

      expect do
        post admin_inventory_bulk_assign_location_path,
             params: { product_id: product.id, quantity: 2, inventory_location_id: shelf.id }
      end.to change { product.inventories.where(inventory_location_id: shelf.id).count }.by(2)

      expect(response).to have_http_status(:see_other)
      # FIFO: se toman las dos más antiguas, la tercera sigue sin ubicar.
      expect(pieces.last.reload.inventory_location_id).to be_nil
    end

    it 'still refuses to assign more units than exist, without partial writes' do
      product = create(:product, skip_seed_inventory: true)
      inventory = create(:inventory, product: product, status: :available, inventory_location: nil)
      warehouse = create(:inventory_location, :warehouse)
      shelf = create(:inventory_location, parent: warehouse)

      expect do
        post admin_inventory_bulk_assign_location_path,
             params: { product_id: product.id, quantity: 5, inventory_location_id: shelf.id }
      end.not_to(change { inventory.reload.inventory_location_id })

      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include('No se asignó ninguna')
    end

    it 'still refuses a non-leaf location' do
      product = create(:product, skip_seed_inventory: true)
      inventory = create(:inventory, product: product, status: :available, inventory_location: nil)
      warehouse = create(:inventory_location, :warehouse)
      create(:inventory_location, parent: warehouse)

      expect do
        post admin_inventory_bulk_assign_location_path,
             params: { product_id: product.id, quantity: 1, inventory_location_id: warehouse.id }
      end.not_to(change { inventory.reload.inventory_location_id })
    end
  end
end
