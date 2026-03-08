# frozen_string_literal: true

require 'rails_helper'
require 'cgi'

RSpec.describe 'SEO meta tags', type: :request do
  before do
    host! 'localhost'
  end

  describe 'GET /catalog with filters' do
    it 'keeps category and brand filters in canonical and aligns og:url' do
      create(:product)

      get catalog_path, params: { brands: ['Tomica'], categories: ['Autos'] }
      expect(response).to have_http_status(:ok)

      canonical = response.body[%r{<link[^>]*rel="canonical"[^>]*href="([^"]+)"}i, 1]
      expect(canonical).to be_present
      expect(CGI.unescapeHTML(canonical)).to eq(catalog_url(brands: ['Tomica'], categories: ['Autos']))

      og_url = response.body[%r{<meta[^>]*property="og:url"[^>]*content="([^"]+)"}i, 1]
      expect(og_url).to eq(canonical)

      robots = response.body[%r{<meta[^>]*name="robots"[^>]*content="([^"]+)"}i, 1]
      expect(robots).to eq('index, follow')
    end

    it 'strips noisy catalog params from canonical and marks page noindex' do
      create(:product)

      get catalog_path, params: {
        q: 'tomica',
        brands: ['Tomica'],
        categories: ['Autos'],
        page: 2,
        sort: 'price_asc'
      }
      expect(response).to have_http_status(:ok)

      canonical = response.body[%r{<link[^>]*rel="canonical"[^>]*href="([^"]+)"}i, 1]
      expect(CGI.unescapeHTML(canonical)).to eq(catalog_url(brands: ['Tomica'], categories: ['Autos']))

      robots = response.body[%r{<meta[^>]*name="robots"[^>]*content="([^"]+)"}i, 1]
      expect(robots).to eq('noindex, follow')
    end
  end

  describe 'auth and internal pages' do
    let(:user) { create(:user) }

    it 'marks sign in page as noindex' do
      get new_user_session_path

      expect(response).to have_http_status(:ok)
      robots = response.body[%r{<meta[^>]*name="robots"[^>]*content="([^"]+)"}i, 1]
      expect(robots).to eq('noindex, nofollow')
    end

    it 'marks checkout pages as noindex' do
      product = create(:product)
      sign_in user
      post cart_items_path, params: { product_id: product.id }

      get checkout_step1_path

      expect(response).to have_http_status(:ok)
      robots = response.body[%r{<meta[^>]*name="robots"[^>]*content="([^"]+)"}i, 1]
      expect(robots).to eq('noindex, nofollow')
    end
  end

  describe 'legal pages' do
    it 'renders unique meta tags for privacy notice' do
      get privacy_notice_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Aviso de Privacidad para Clientes |')
      expect(response.body).to include('tratamiento de datos personales')
      expect(response.body).to include(%(href="#{privacy_notice_url}"))
    end

    it 'renders unique meta tags for terms page' do
      get terms_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Términos y Condiciones |')
      expect(response.body).to include('uso del sitio, compras, pagos')
      expect(response.body).to include(%(href="#{terms_url}"))
    end
  end
end
