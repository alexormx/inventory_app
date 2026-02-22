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
  end
end
