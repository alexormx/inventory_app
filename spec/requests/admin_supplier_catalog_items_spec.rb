require 'rails_helper'

RSpec.describe "Admin::SupplierCatalogItems", type: :request do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: :admin) }
  let!(:catalog_item) { create(:supplier_catalog_item) }

  before do
    login_as(admin, scope: :user)
  end

  describe "GET /admin/supplier_catalog_items" do
    it "renders the index" do
      get admin_supplier_catalog_items_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Catálogo proveedor")
      expect(response.body).to include(catalog_item.canonical_name)
    end
  end

  describe "POST /admin/supplier_catalog_items/:id/create_product" do
    it "creates and links a product" do
      expect do
        post create_product_admin_supplier_catalog_item_path(catalog_item)
      end.to change(Product, :count).by(1)

      expect(response).to redirect_to(admin_supplier_catalog_item_path(catalog_item))
      expect(catalog_item.reload.product).to be_present
    end
  end

  describe "POST /admin/supplier_catalog_items/:id/link_product" do
    it "links an existing product by identifier" do
      product = create(:product, skip_seed_inventory: true)

      post link_product_admin_supplier_catalog_item_path(catalog_item), params: { product_identifier: product.product_sku }

      expect(response).to redirect_to(admin_supplier_catalog_item_path(catalog_item))
      expect(catalog_item.reload.product).to eq(product)
    end
  end

  describe "POST /admin/supplier_catalog_items/:id/refresh_takara_tomy_mall" do
    it "refreshes the Takara source manually" do
      service = instance_double(Suppliers::TakaraTomyMall::BackfillItemService, call: true)
      allow(Suppliers::TakaraTomyMall::BackfillItemService).to receive(:new).with(catalog_item).and_return(service)

      post refresh_takara_tomy_mall_admin_supplier_catalog_item_path(catalog_item)

      expect(response).to redirect_to(admin_supplier_catalog_item_path(catalog_item))
      expect(Suppliers::TakaraTomyMall::BackfillItemService).to have_received(:new).with(catalog_item)
    end
  end
end