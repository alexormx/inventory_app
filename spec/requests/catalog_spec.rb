# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Catalog browsing", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /catalog" do
    it "lists products with default sort (newest)" do
      old = create(:product, created_at: 2.days.ago)
      recent = create(:product, created_at: 1.hour.ago)

      get catalog_path
      expect(response).to have_http_status(:ok)
      # recent should appear before old
      expect(response.body.index(recent.product_name)).to be < response.body.index(old.product_name)
    end

    it "filters by query (q) across name/category/brand" do
      p1 = create(:product, product_name: "Tomica Supra GT")
      p2 = create(:product, brand: "HotWheels", product_name: "Generic Car")

      get catalog_path, params: { q: 'tomica' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(p1.product_name)
      expect(response.body).not_to include(p2.product_name)
    end

    it "supports sorting by price asc/desc and name asc" do
      cheap = create(:product, selling_price: 10)
      pricey = create(:product, selling_price: 20)
      a_name = create(:product, product_name: 'Alpha Zed')
      z_name = create(:product, product_name: 'Zulu Car')

      get catalog_path, params: { sort: 'price_asc' }
      expect(response).to have_http_status(:ok)
      expect(response.body.index(cheap.product_name)).to be < response.body.index(pricey.product_name)

      get catalog_path, params: { sort: 'price_desc' }
      expect(response.body.index(pricey.product_name)).to be < response.body.index(cheap.product_name)

      get catalog_path, params: { sort: 'name_asc' }
      expect(response.body.index(a_name.product_name)).to be < response.body.index(z_name.product_name)
    end

    it "filters by categories and brands" do
      cat_a = create(:product, category: 'Autos', brand: 'Tomica')
      cat_b = create(:product, category: 'Aviones', brand: 'Takara')
      get catalog_path, params: { categories: ['Autos'], brands: ['Tomica'] }
      expect(response.body).to include(cat_a.product_name)
      expect(response.body).not_to include(cat_b.product_name)
    end

    it "filters by price range" do
      low = create(:product, selling_price: 5)
      mid = create(:product, selling_price: 10)
      high = create(:product, selling_price: 50)
      get catalog_path, params: { price_min: 6, price_max: 20 }
      expect(response.body).to include(mid.product_name)
      expect(response.body).not_to include(low.product_name)
      expect(response.body).not_to include(high.product_name)
    end

    it "filters by in_stock, backorder, preorder" do
      in_stock = create(:product)
      create(:inventory, product: in_stock, status: :available, purchase_cost: 1)
      bo = create(:product, backorder_allowed: true, skip_seed_inventory: true)
      po = create(:product, preorder_available: true, skip_seed_inventory: true)

      get catalog_path, params: { in_stock: '1' }
      expect(response.body).to include(in_stock.product_name)
      expect(response.body).not_to include(bo.product_name)

      get catalog_path, params: { backorder: '1' }
      expect(response.body).to include(bo.product_name)
      expect(response.body).not_to include(po.product_name)

      get catalog_path, params: { preorder: '1' }
      expect(response.body).to include(po.product_name)
      expect(response.body).not_to include(bo.product_name)
    end
  end
end
