# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin user details', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user, name: 'Cliente de prueba') }

  describe 'GET /admin/users/:id' do
    it 'renders the user detail page for an administrator' do
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(customer.name)
      expect(response.body).to include(customer.email)
    end

    it 'returns not found for a missing user' do
      sign_in admin

      get admin_user_path(id: 0)

      expect(response).to have_http_status(:not_found)
    end

    it 'redirects a non-admin user to the root page' do
      sign_in customer

      get admin_user_path(admin)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include('Acceso denegado')
    end

    it 'redirects an unauthenticated user to sign in' do
      get admin_user_path(customer)

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
