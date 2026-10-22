# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::ApiGuide', type: :request do
  include Warden::Test::Helpers

  after { Warden.test_reset! }

  it 'denies access to customers' do
    login_as(create(:user), scope: :user)
    get admin_api_guide_path
    expect(response).to redirect_to(root_path)
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
      expect(response.body).to include('product[product_images][]', 'image_urls', 'Bearer', '/api-docs')
    end

    it 'lists the endpoints from the OpenAPI file with the permission each needs' do
      get admin_api_guide_path
      expect(response.body).to include('/api/v1/products/{id}', 'PATCH', 'products:write')
      expect(response.body).to include('/api/v1/sale_order_items', 'Solo token de administrador')
    end

    it 'serves the OpenAPI file behind the interactive reference' do
      get '/api-docs/v1/swagger.yaml'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('/api/v1/products/{id}')
    end
  end
end
