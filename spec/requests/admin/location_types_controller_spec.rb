# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::LocationTypesController, type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:location_type) { create(:location_type, name: 'Test Type', code: 'test_type') }

  before do
    sign_in admin
  end

  describe 'GET /admin/location_types' do
    it 'returns http success' do
      get admin_location_types_path
      expect(response).to have_http_status(:success)
    end

    it 'displays all location types' do
      get admin_location_types_path
      expect(response.body).to include('Test Type')
    end
  end

  describe 'GET /admin/location_types/new' do
    it 'returns http success' do
      get new_admin_location_type_path
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /admin/location_types' do
    let(:valid_params) do
      {
        location_type: {
          name: 'New Type',
          code: 'new_type',
          icon: 'bi-box',
          color: 'primary',
          position: 10,
          active: true
        }
      }
    end

    it 'creates a new location type' do
      expect {
        post admin_location_types_path, params: valid_params
      }.to change(LocationType, :count).by(1)
    end

    it 'redirects to index with success message' do
      post admin_location_types_path, params: valid_params
      expect(response).to redirect_to(admin_location_types_path)
      follow_redirect!
      expect(response.body).to include('creado exitosamente')
    end

    context 'with invalid params' do
      it 'renders new with errors' do
        post admin_location_types_path, params: { location_type: { name: '' } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /admin/location_types/:id/edit' do
    it 'returns http success' do
      get edit_admin_location_type_path(location_type)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'PATCH /admin/location_types/:id' do
    it 'updates the location type' do
      patch admin_location_type_path(location_type), params: {
        location_type: { name: 'Updated Name' }
      }
      expect(location_type.reload.name).to eq('Updated Name')
    end

    it 'redirects to index with success message' do
      patch admin_location_type_path(location_type), params: {
        location_type: { name: 'Updated Name' }
      }
      expect(response).to redirect_to(admin_location_types_path)
    end
  end

  describe 'DELETE /admin/location_types/:id' do
    context 'when no locations use this type' do
      it 'deletes the location type' do
        expect {
          delete admin_location_type_path(location_type)
        }.to change(LocationType, :count).by(-1)
      end
    end

    context 'when locations use this type' do
      before do
        LocationType.seed_defaults! unless LocationType.find_by(code: 'warehouse')
        create(:inventory_location, location_type: location_type.code)
      end

      it 'does not delete and shows error' do
        expect {
          delete admin_location_type_path(location_type)
        }.not_to change(LocationType, :count)
        expect(response).to redirect_to(admin_location_types_path)
      end
    end
  end

  describe 'PATCH /admin/location_types/:id/move' do
    let!(:type1) { create(:location_type, position: 0) }
    let!(:type2) { create(:location_type, position: 1) }
    let!(:type3) { create(:location_type, position: 2) }

    it 'moves type up' do
      patch move_admin_location_type_path(type2, direction: 'up')
      expect(type2.reload.position).to eq(0)
      expect(type1.reload.position).to eq(1)
    end

    it 'moves type down' do
      patch move_admin_location_type_path(type2, direction: 'down')
      expect(type2.reload.position).to eq(2)
      expect(type3.reload.position).to eq(1)
    end

    it 'redirects to index' do
      patch move_admin_location_type_path(type2, direction: 'up')
      expect(response).to redirect_to(admin_location_types_path)
    end
  end
end
