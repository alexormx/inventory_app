# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SEO meta tags', type: :request do
  let(:user) { create(:user) }

  before do
    host! 'localhost'
    sign_in user
  end

  describe 'GET /catalog with filters' do
    it 'uses canonical /catalog (no query params) and aligns og:url' do
      create(:product)

      get catalog_path, params: { q: 'tomica', brands: ['Tomica'], page: 2 }
      expect(response).to have_http_status(:ok)

      canonical = response.body[%r{<link[^>]*rel="canonical"[^>]*href="([^"]+)"}i, 1]
      expect(canonical).to be_present
      expect(canonical).to end_with('/catalog')
      expect(canonical).not_to include('?')

      og_url = response.body[%r{<meta[^>]*property="og:url"[^>]*content="([^"]+)"}i, 1]
      expect(og_url).to eq(canonical)
    end
  end
end
