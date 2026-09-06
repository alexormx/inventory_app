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

    it 'renders a customer with a saved default shipping address' do
      address = create(:shipping_address, user: customer, full_name: 'Ana Destinataria',
                                          line1: 'Calle Roble 123', line2: 'Interior 4')
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(address.full_name, address.line1)
    end

    it 'orders multiple addresses with the default first and renders both' do
      secondary = create(:shipping_address, user: customer, full_name: 'Segundo Destino', default: false,
                                            state: nil)
      primary = create(:shipping_address, user: customer, full_name: 'Destino Principal', default: true)
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include(primary.full_name, secondary.full_name)
      addresses_card = document.css('h5').find { |h| h.text.include?('Direcciones de Envío') }.ancestors('.card').first
      expect(addresses_card.css('.badge').map(&:text)).to eq(['Principal'])
    end

    it 'renders a customer with no saved shipping addresses' do
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
    end
  end
end
