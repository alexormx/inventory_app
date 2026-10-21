# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::ApiKeys', type: :request do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }

  after { Warden.test_reset! }

  context 'as a customer' do
    it 'denies access' do
      login_as(create(:user), scope: :user)
      get admin_api_keys_path
      expect(response).to redirect_to(root_path)
    end
  end

  context 'as an admin' do
    before { login_as(admin, scope: :user) }

    it 'lists keys with prefix, scopes and never-used state' do
      key = create(:api_key, name: 'KataFrame laptop', token_prefix: 'pk_AbCdEfGh', scopes: ['products:read'])
      get admin_api_keys_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('KataFrame laptop', 'pk_AbCdEfGh', 'Leer productos', 'Nunca')
      expect(response.body).to include(revoke_admin_api_key_path(key))
    end

    it 'shows the new form with every scope checked' do
      get new_admin_api_key_path
      expect(response).to have_http_status(:ok)
      ApiKey::SCOPES.each do |scope|
        expect(response.body).to match(/value="#{scope}"[^>]*checked/)
      end
    end

    it 'creates a key and shows its token only once' do
      expect do
        post admin_api_keys_path, params: { api_key: { name: 'KataFrame', scopes: ApiKey::SCOPES } }
      end.to change(ApiKey, :count).by(1)

      token = response.body[/pk_[1-9A-HJ-NP-Za-km-z]{40}/]
      expect(token).to be_present
      expect(response.body).to include('no se volverá a mostrar')
      expect(ApiKey.authenticate(token)).to eq(ApiKey.last)

      get admin_api_keys_path
      expect(response.body).not_to include(token)
    end

    it 'does not create a key without scopes' do
      expect do
        post admin_api_keys_path, params: { api_key: { name: 'KataFrame', scopes: [''] } }
      end.not_to change(ApiKey, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'revokes a key' do
      key = create(:api_key)
      patch revoke_admin_api_key_path(key)
      expect(response).to redirect_to(admin_api_keys_path)
      expect(key.reload).to be_revoked

      get admin_api_keys_path
      expect(response.body).to include('Revocada')
      expect(response.body).not_to include(revoke_admin_api_key_path(key))
    end
  end
end
