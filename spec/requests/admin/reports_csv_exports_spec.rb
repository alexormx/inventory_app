# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe 'Admin CSV exports', type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    sign_in admin
  end

  describe 'GET /admin/inventory.csv' do
    it 'includes category column in inventory summary export' do
      create(:product, skip_seed_inventory: true, product_name: 'Mini GT', product_sku: 'MGT-001', category: 'diecast')

      get admin_inventory_path(format: :csv)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/csv')

      parsed = CSV.parse(response.body, headers: true)
      expect(parsed.headers).to include('Category')
      target_row = parsed.find { |row| row['SKU'] == 'MGT-001' }
      expect(target_row).to be_present
      expect(target_row['Category']).to eq('diecast')
    end
  end

  describe 'GET /admin/reports/inventory_items' do
    it 'includes category column in all inventory items export' do
      product = create(:product, skip_seed_inventory: true, product_name: 'Figura X', product_sku: 'FIG-X', category: 'collectibles')
      create(:inventory, product: product, status: :available, purchase_cost: 10)

      get inventory_items_admin_reports_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/csv')

      parsed = CSV.parse(response.body, headers: true)
      expect(parsed.headers).to include('Category')
      target_row = parsed.find { |row| row['SKU'] == 'FIG-X' }
      expect(target_row).to be_present
      expect(target_row['Category']).to eq('collectibles')
    end
  end

  describe 'GET /admin/reports/inventory_items_with_locations' do
    it 'exports only inventory items with location and includes location details' do
      location = create(:inventory_location, :warehouse, name: 'Bodega Norte', code: 'BDG-N')
      located_product = create(:product, skip_seed_inventory: true, product_name: 'Auto A', product_sku: 'AUTO-A', category: 'diecast')
      unlocated_product = create(:product, skip_seed_inventory: true, product_name: 'Auto B', product_sku: 'AUTO-B', category: 'diecast')

      create(:inventory, product: located_product, status: :available, inventory_location: location, purchase_cost: 12)
      create(:inventory, product: unlocated_product, status: :available, inventory_location_id: nil, purchase_cost: 15)

      get inventory_items_with_locations_admin_reports_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/csv')

      parsed = CSV.parse(response.body, headers: true)
      expect(parsed.headers).to include('Location Code', 'Location Path', 'Category')

      located_row = parsed.find { |row| row['SKU'] == 'AUTO-A' }
      expect(located_row).to be_present
      expect(located_row['Location Code']).to eq('BDG-N')
      expect(located_row['Location Path']).to include('Bodega Norte')

      unlocated_row = parsed.find { |row| row['SKU'] == 'AUTO-B' }
      expect(unlocated_row).to be_nil
    end
  end
end