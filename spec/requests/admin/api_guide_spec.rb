# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::ApiGuide', type: :request do
  include Warden::Test::Helpers

  after { Warden.test_reset! }

  it 'denies access to customers' do
    login_as(create(:user), scope: :user)
    [admin_api_guide_path, admin_api_guide_reference_path, admin_api_guide_openapi_path].each do |path|
      get path
      expect(response).to redirect_to(root_path)
    end
  end

  it 'sends old /api-docs bookmarks to the admin reference' do
    get '/api-docs'
    expect(response).to redirect_to(admin_api_guide_reference_path)
  end

  context 'as an admin' do
    before { login_as(create(:user, :admin), scope: :user) }

    it 'is reachable from the API keys page' do
      get admin_api_keys_path
      expect(response.body).to include(admin_api_guide_path)
    end

    it 'explains the KataFrame setup and links the interactive reference' do
      get admin_api_guide_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('product[product_images][]', 'image_urls', 'Bearer', admin_api_guide_reference_path)
    end

    it 'lists the endpoints from the OpenAPI file with the permission each needs' do
      get admin_api_guide_path
      expect(response.body).to include('/api/v1/products/{id}', 'PATCH', 'products:write')
      expect(response.body).to include('/api/v1/sale_order_items', 'Solo token de administrador')
    end

    it 'renders the interactive reference inside the admin layout' do
      get admin_api_guide_reference_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="sidebar"', 'data-controller="swagger-ui"', admin_api_guide_openapi_path)
      expect(response.body).not_to include('Api Guide')
    end

    it 'serves the OpenAPI document pointed at the current host' do
      get admin_api_guide_openapi_path
      expect(response).to have_http_status(:ok)
      doc = JSON.parse(response.body)
      expect(doc['paths']).to include('/api/v1/products/{id}')
      expect(doc['servers']).to eq([{ 'url' => 'http://www.example.com' }])
    end
  end
end
