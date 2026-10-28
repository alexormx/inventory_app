# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Favorites', type: :request do
  let(:user) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true, product_name: 'Tomica Toyota 2000GT') }

  describe 'without a session' do
    it 'asks to sign in before saving and keeps the product to save afterwards' do
      get favorites_path(add: product.id)

      expect(response).to redirect_to(new_user_session_path)

      post user_session_path, params: { user: { email: user.email, password: user.password } }
      follow_redirect!

      expect(Favorite.open.where(user: user, product: product)).to exist
    end

    it 'does not accept a save' do
      post favorites_path, params: { product_id: product.id }

      expect(Favorite.count).to eq(0)
    end
  end

  describe 'with a session' do
    before { sign_in user }

    it 'saves a product and swaps the heart without reloading' do
      post favorites_path, params: { product_id: product.id }, as: :turbo_stream

      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include("favorite_heart_#{product.id}")
      expect(Favorite.open.where(user: user, product: product)).to exist
    end

    it 'removes a product from the list' do
      Favorite.save_for(user, product)

      delete favorite_path(product.id), as: :turbo_stream

      expect(Favorite.open).to be_empty
    end

    it 'lists only the open favorites of the customer' do
      Favorite.save_for(user, product)
      Favorite.save_for(user, create(:product, skip_seed_inventory: true, product_name: 'Ya lo quité')).remove!
      Favorite.save_for(create(:user), create(:product, skip_seed_inventory: true, product_name: 'De otro cliente'))

      get favorites_path

      expect(response.body).to include('Tomica Toyota 2000GT')
      expect(response.body).not_to include('Ya lo quité')
      expect(response.body).not_to include('De otro cliente')
    end

    it 'shows the heart filled on the product page once saved' do
      Favorite.save_for(user, product)

      get product_path(product)

      expect(response.body).to include("favorite_heart_#{product.id}")
      expect(response.body).to include('Quitar de favoritos')
    end

    it 'never shows supplier identifiers on the list' do
      product.update_columns(product_sku: 'SUPPLIER-SKU-123')
      Favorite.save_for(user, product)

      get favorites_path

      expect(response.body).not_to include('SUPPLIER-SKU-123')
    end
  end
end
