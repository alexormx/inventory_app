require 'rails_helper'

RSpec.describe 'Admin::Products search', type: :request do
  let!(:product1) { create(:product, product_name: "Alpha Widget", product_sku: "ALP-001") }
  let!(:product2) { create(:product, product_name: "Beta Gadget", product_sku: "BET-002") }
  let!(:product3) { create(:product, product_name: "Gamma Tool", product_sku: "GAM-003") }

  before do
    sign_in create(:user, :admin)
  end

  it "returns empty array when query blank" do
    get search_admin_products_path
    expect(response).to have_http_status(:ok)
  expect(response.parsed_body).to eq([])
  end

  it "returns matches with >=3 chars" do
    get search_admin_products_path(query: 'alp')
  json = response.parsed_body
    expect(json.any? { |p| p['id'] == product1.id }).to be_truthy
  end

  it "filters by partial SKU" do
    get search_admin_products_path(query: 'BET')
  json = response.parsed_body
    expect(json.any? { |p| p['id'] == product2.id }).to be_truthy
  end

  it "limits result set" do
    get search_admin_products_path(query: 'a') # length 1 returns []
    expect(JSON.parse(response.body)).to eq([])
  end
end
