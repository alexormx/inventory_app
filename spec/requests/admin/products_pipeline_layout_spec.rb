# frozen_string_literal: true

require 'rails_helper'

# Las pestañas del pipeline sirven para dos cosas a la vez: son el destino de
# turbo-frame#products_frame y también páginas a las que se puede entrar por URL.
# Sin layout en el segundo caso la respuesta llegaba sin JS y los botones de
# activar/inactivar dejaban de funcionar.
RSpec.describe 'Admin products pipeline layout', type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  shared_examples 'a dual-mode pipeline tab' do |path_helper|
    it 'serves a full document on direct navigation so Turbo can boot' do
      get public_send(path_helper)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<html')
      expect(response.body).to include('</head>')
      # Sin el bundle admin (que importa Turbo) data-turbo-method degrada a GET.
      expect(response.body).to match(%r{<script[^>]+src="[^"]*/admin-[^"]*\.js"})
      expect(response.body).to include('turbo-frame')
    end

    it 'serves only the frame when Turbo requests it' do
      get public_send(path_helper), headers: { 'Turbo-Frame' => 'products_frame' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('products_frame')
      expect(response.body).not_to include('<html')
      expect(response.body).not_to include('</head>')
    end
  end

  describe 'GET /admin/products/drafts' do
    before { create(:product, status: 'draft') }

    it_behaves_like 'a dual-mode pipeline tab', :admin_products_drafts_path
  end

  describe 'GET /admin/products/active' do
    before { create(:product, status: 'active') }

    it_behaves_like 'a dual-mode pipeline tab', :admin_products_active_path
  end

  describe 'GET /admin/products/inactive' do
    before { create(:product, status: 'inactive') }

    it_behaves_like 'a dual-mode pipeline tab', :admin_products_inactive_path
  end

  describe 'state changes stay off GET' do
    it 'does not expose activate over GET and leaves the product alone' do
      product = create(:product, status: 'draft')

      expect do
        get "/admin/products/#{product.to_param}/activate"
      end.not_to(change { product.reload.status })

      expect(response).to have_http_status(:not_found)
    end
  end
end
