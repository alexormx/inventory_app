# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::InventoryLocations', type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    sign_in admin
  end

  describe 'GET /admin/inventory_locations' do
    it 'returns success' do
      get admin_inventory_locations_path
      expect(response).to have_http_status(:success)
    end

    it 'displays existing locations' do
      warehouse = create(:inventory_location, :warehouse, name: 'Bodega Test')
      get admin_inventory_locations_path
      expect(response.body).to include('Bodega Test')
    end
  end

  describe 'GET /admin/inventory_locations/new' do
    it 'returns success' do
      get new_admin_inventory_location_path
      expect(response).to have_http_status(:success)
    end

    it 'pre-selects parent when provided' do
      warehouse = create(:inventory_location, :warehouse)
      get new_admin_inventory_location_path(parent_id: warehouse.id)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /admin/inventory_locations' do
    it 'creates a new location' do
      expect {
        post admin_inventory_locations_path, params: {
          inventory_location: {
            name: 'Nueva Bodega',
            location_type: 'warehouse'
          }
        }
      }.to change(InventoryLocation, :count).by(1)

      expect(response).to redirect_to(admin_inventory_locations_path)
      follow_redirect!
      expect(response.body).to include('Nueva Bodega')
    end

    it 'creates a child location' do
      parent = create(:inventory_location, :warehouse)

      expect {
        post admin_inventory_locations_path, params: {
          inventory_location: {
            name: 'Sección A',
            location_type: 'section',
            parent_id: parent.id
          }
        }
      }.to change(InventoryLocation, :count).by(1)

      new_location = InventoryLocation.last
      expect(new_location.parent).to eq(parent)
    end

    it 'renders errors for invalid data' do
      post admin_inventory_locations_path, params: {
        inventory_location: {
          name: '',
          location_type: 'invalid'
        }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /admin/inventory_locations/:id' do
    let!(:location) { create(:inventory_location, :warehouse, name: 'Old Name') }

    it 'updates the location' do
      patch admin_inventory_location_path(location), params: {
        inventory_location: { name: 'New Name' }
      }

      expect(response).to redirect_to(admin_inventory_locations_path)
      expect(location.reload.name).to eq('New Name')
    end
  end

  describe 'DELETE /admin/inventory_locations/:id' do
    it 'deletes a leaf location without inventory' do
      location = create(:inventory_location, :warehouse)

      expect {
        delete admin_inventory_location_path(location)
      }.to change(InventoryLocation, :count).by(-1)

      expect(response).to redirect_to(admin_inventory_locations_path)
    end

    it 'prevents deletion of location with children' do
      parent = create(:inventory_location, :warehouse)
      create(:inventory_location, :section, parent: parent)

      expect {
        delete admin_inventory_location_path(parent)
      }.not_to change(InventoryLocation, :count)

      expect(response).to redirect_to(admin_inventory_locations_path)
      follow_redirect!
      expect(response.body).to include('sub-ubicaciones')
    end
  end

  describe 'GET /admin/inventory_locations/:id' do
    it 'shows location details' do
      location = create(:inventory_location, :warehouse, name: 'Mi Bodega')
      get admin_inventory_location_path(location)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Mi Bodega')
    end
  end

  describe 'GET /admin/inventory_locations/tree' do
    it 'returns JSON tree structure' do
      warehouse = create(:inventory_location, :warehouse)
      section = create(:inventory_location, :section, parent: warehouse)

      get tree_admin_inventory_locations_path, as: :json

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.first['children']).to be_present
    end
  end

  describe 'GET /admin/inventory_locations/options' do
    it 'returns options for select dropdowns' do
      create(:inventory_location, :warehouse, name: 'Bodega A')
      create(:inventory_location, :warehouse, name: 'Bodega B')

      get options_admin_inventory_locations_path, as: :json

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json.map { |o| o['label'] }).to include('Bodega A', 'Bodega B')
    end
  end
end
