# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sitemap', type: :request do
  before do
    host! 'localhost'
  end

  describe 'GET /sitemap.xml' do
    it 'does not include parameterized URLs and uses ActiveStorage proxy URLs for images' do
      create(:product)

      get '/sitemap.xml'
      expect(response).to have_http_status(:ok)

      locs = response.body.scan(%r{<loc>([^<]+)</loc>}i).flatten
      expect(locs).not_to be_empty
      expect(locs).to all(satisfy { |url| !url.include?('?') })

      expect(response.body).to include('/rails/active_storage/blobs/proxy/')
      expect(response.body).not_to include('/rails/active_storage/blobs/redirect/')
      expect(response.body).not_to include('categories%5B%5D=')
      expect(response.body).not_to include('brands%5B%5D=')
    end
  end
end
