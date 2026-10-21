# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API key authentication', type: :request do
  let(:admin) { create(:user, :admin) }

  def key_with(scopes)
    ApiKey.generate!(name: 'KataFrame', scopes: scopes, created_by: admin)
  end

  def bearer(token, scheme: 'Bearer')
    { 'Authorization' => "#{scheme} #{token}" }
  end

  def json
    JSON.parse(response.body)
  end

  describe 'GET /api/v1/catalog' do
    it 'rejects a request without Authorization' do
      get '/api/v1/catalog'
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq('error' => 'Unauthorized')
    end

    it 'rejects an unknown pk_ token' do
      get '/api/v1/catalog', headers: bearer('pk_basura')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a revoked key' do
      key, token = key_with(ApiKey::SCOPES)
      key.revoke!
      get '/api/v1/catalog', headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a key whose creator is no longer an admin' do
      _key, token = key_with(ApiKey::SCOPES)
      admin.update_column(:role, 'customer')
      get '/api/v1/catalog', headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'accepts a key with products:read and records its use' do
      key, token = key_with(['products:read'])
      get '/api/v1/catalog', headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(key.reload.last_used_at).to be_present
    end

    it 'accepts a lowercase bearer scheme' do
      _key, token = key_with(['products:read'])
      get '/api/v1/catalog', headers: bearer(token, scheme: 'bearer')
      expect(response).to have_http_status(:ok)
    end

    it 'forbids a key without products:read' do
      _key, token = key_with(['photos:write'])
      get '/api/v1/catalog', headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq('error' => 'Forbidden: missing scope products:read')
    end

    it 'keeps accepting the legacy admin token with Token and Bearer schemes' do
      admin.update_column(:api_token, SecureRandom.hex(20))
      get '/api/v1/catalog', headers: bearer(admin.api_token, scheme: 'Token')
      expect(response).to have_http_status(:ok)
      get '/api/v1/catalog', headers: bearer(admin.api_token)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'order endpoints' do
    it 'forbid API keys even with every scope' do
      _key, token = key_with(ApiKey::SCOPES)
      post '/api/v1/sales_orders', params: { sale_order: {} }, headers: bearer(token)
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq('error' => 'Forbidden: API keys cannot access this endpoint')
    end

    it 'still authenticate the legacy token' do
      admin.update_column(:api_token, SecureRandom.hex(20))
      post '/api/v1/sales_orders', params: { sale_order: {} }, headers: bearer(admin.api_token)
      expect(response.status).not_to be_in([401, 403])
    end
  end
end
