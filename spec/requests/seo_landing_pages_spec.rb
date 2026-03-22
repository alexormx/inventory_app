# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SEO Landing Pages', type: :request do
  before do
    host! 'localhost'
  end

  describe 'GET /marca/:brand_slug (brand landing)' do
    let!(:product) { create(:product, brand: 'Tomica', category: 'diecast', status: 'active') }

    it 'renders catalog filtered by brand with SEO meta tags' do
      get brand_landing_path(brand_slug: 'tomica')

      expect(response).to have_http_status(:ok)

      # Title includes brand name and site name
      expect(response.body).to include('Tomica')
      expect(response.body).to include('Pasatiempos')

      # Canonical points to the clean brand URL, not /catalog?brands[]=
      canonical = response.body[%r{<link[^>]*rel="canonical"[^>]*href="([^"]+)"}i, 1]
      expect(canonical).to include('/marca/tomica')
      expect(canonical).not_to include('brands')

      # Robots allows indexing
      robots = response.body[%r{<meta[^>]*name="robots"[^>]*content="([^"]+)"}i, 1]
      expect(robots).to eq('index, follow')

      # CollectionPage JSON-LD present
      expect(response.body).to include('CollectionPage')
      expect(response.body).to include(product.product_name)
    end

    it 'shows the product in results' do
      get brand_landing_path(brand_slug: 'tomica')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.product_name)
    end

    it 'redirects to catalog when brand slug not found' do
      get brand_landing_path(brand_slug: 'nonexistent-brand-xyz')

      expect(response).to redirect_to(catalog_path)
    end
  end

  describe 'GET /categoria/:category_slug (category landing)' do
    let!(:product) { create(:product, category: 'diecast', brand: 'Tomica', status: 'active') }

    it 'renders catalog filtered by category with SEO meta tags' do
      get category_landing_path(category_slug: 'diecast')

      expect(response).to have_http_status(:ok)

      # Title includes category name
      expect(response.body).to include('diecast')

      # Canonical points to clean category URL
      canonical = response.body[%r{<link[^>]*rel="canonical"[^>]*href="([^"]+)"}i, 1]
      expect(canonical).to include('/categoria/diecast')
      expect(canonical).not_to include('categories')

      # Robots allows indexing
      robots = response.body[%r{<meta[^>]*name="robots"[^>]*content="([^"]+)"}i, 1]
      expect(robots).to eq('index, follow')
    end

    it 'redirects to catalog when category slug not found' do
      get category_landing_path(category_slug: 'nonexistent-category-xyz')

      expect(response).to redirect_to(catalog_path)
    end
  end

  describe 'GET /serie/:series_slug (series landing)' do
    let!(:product) { create(:product, series: 'Limited Vintage', category: 'diecast', brand: 'Tomica', status: 'active') }

    it 'renders catalog filtered by series with SEO meta tags' do
      get series_landing_path(series_slug: 'limited-vintage')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Limited Vintage')

      canonical = response.body[%r{<link[^>]*rel="canonical"[^>]*href="([^"]+)"}i, 1]
      expect(canonical).to include('/serie/limited-vintage')
      expect(canonical).not_to include('series')

      robots = response.body[%r{<meta[^>]*name="robots"[^>]*content="([^"]+)"}i, 1]
      expect(robots).to eq('index, follow')
    end

    it 'redirects to catalog when series slug not found' do
      get series_landing_path(series_slug: 'nonexistent-series-xyz')

      expect(response).to redirect_to(catalog_path)
    end
  end

  describe 'Sitemap includes brand and category landing pages' do
    let!(:product) { create(:product, brand: 'Tomica', category: 'diecast', series: 'Limited Vintage', status: 'active') }

    it 'includes /marca/tomica, /categoria/diecast and /serie/limited-vintage in sitemap' do
      get '/sitemap.xml'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('/marca/tomica')
      expect(response.body).to include('/categoria/diecast')
      expect(response.body).to include('/serie/limited-vintage')
    end
  end
end
