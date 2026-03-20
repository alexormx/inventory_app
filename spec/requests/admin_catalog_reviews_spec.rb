# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::CatalogReviews", type: :request do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: :admin) }

  before { login_as(admin, scope: :user) }

  describe "GET /admin/catalog_review" do
    it "renders the review page" do
      get admin_catalog_review_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Revisión de Catálogo")
    end

    context "with no matching products" do
      it "shows empty state" do
        # All products linked with matching data — no issues
        get admin_catalog_review_path(modes: ["mismatch"])
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No hay productos pendientes de revisión")
      end
    end

    context "with unlinked products" do
      let!(:unlinked_product) { create(:product, skip_seed_inventory: true) }

      it "shows the unlinked product" do
        get admin_catalog_review_path(modes: ["unlinked"])
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(unlinked_product.product_name)
        expect(response.body).to include("No vinculado")
        expect(response.body).to include("Producto 1 de")
      end
    end

    context "with linked product missing data" do
      let!(:product) { create(:product, skip_seed_inventory: true, barcode: nil) }
      let!(:catalog_item) { create(:supplier_catalog_item, product: product) }

      it "shows the product in missing_data mode" do
        get admin_catalog_review_path(modes: ["missing_data"])
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(product.product_name)
      end
    end

    context "with barcode mismatch" do
      let!(:product) { create(:product, skip_seed_inventory: true, barcode: "111", supplier_product_code: "AAA") }
      let!(:catalog_item) { create(:supplier_catalog_item, product: product, barcode: "222", supplier_product_code: "BBB") }

      it "shows the product in mismatch mode" do
        get admin_catalog_review_path(modes: ["mismatch"])
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(product.product_name)
        expect(response.body).to include("Diferente")
      end
    end

    context "with low name similarity" do
      let!(:product) { create(:product, skip_seed_inventory: true, product_name: "Completely Different Name XYZ") }
      let!(:catalog_item) { create(:supplier_catalog_item, product: product, canonical_name: "Lamborghini Temerario No.43") }

      it "shows the product in low_similarity mode" do
        get admin_catalog_review_path(modes: ["low_similarity"])
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(product.product_name)
      end
    end

    context "with reviewed products" do
      let!(:product) { create(:product, skip_seed_inventory: true) }
      let!(:review) { create(:product_catalog_review, product: product) }

      it "excludes reviewed products by default" do
        get admin_catalog_review_path(modes: ["unlinked"])
        expect(response.body).not_to include(product.product_name)
      end

      it "includes reviewed products when show_reviewed=1" do
        get admin_catalog_review_path(modes: ["unlinked"], show_reviewed: "1")
        expect(response.body).to include(product.product_name)
        expect(response.body).to include("Revisado")
      end
    end

    context "navigation index clamping" do
      let!(:product) { create(:product, skip_seed_inventory: true) }

      it "clamps index to valid range" do
        get admin_catalog_review_path(modes: ["unlinked"], index: 999)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(product.product_name)
      end
    end

    context "text search" do
      let!(:product_a) { create(:product, skip_seed_inventory: true, product_name: "Alpha Tomica Car") }
      let!(:product_b) { create(:product, skip_seed_inventory: true, product_name: "Beta Hotwheels Truck") }

      it "filters by search query" do
        get admin_catalog_review_path(modes: ["unlinked"], q: "Alpha")
        expect(response.body).to include("Alpha Tomica Car")
        expect(response.body).not_to include("Beta Hotwheels Truck")
      end
    end
  end

  describe "POST /admin/catalog_review/link" do
    let!(:product) { create(:product, skip_seed_inventory: true) }
    let!(:catalog_item) { create(:supplier_catalog_item) }

    it "links the product to the catalog item" do
      post link_admin_catalog_review_path, params: {
        product_id: product.id,
        catalog_item_id: catalog_item.id,
        index: 0, modes: ["unlinked"]
      }

      expect(response).to redirect_to(admin_catalog_review_path(modes: ["unlinked"], index: "0", show_reviewed: nil, q: nil))
      expect(catalog_item.reload.product_id).to eq(product.id)
    end
  end

  describe "POST /admin/catalog_review/unlink" do
    let!(:product) { create(:product, skip_seed_inventory: true) }
    let!(:catalog_item) { create(:supplier_catalog_item, product: product) }

    it "unlinks the product" do
      post unlink_admin_catalog_review_path, params: {
        product_id: product.id,
        index: 0, modes: ["missing_data"]
      }

      expect(response).to have_http_status(:redirect)
      expect(catalog_item.reload.product_id).to be_nil
    end
  end

  describe "POST /admin/catalog_review/sync_fields" do
    let!(:product) { create(:product, skip_seed_inventory: true, barcode: nil, supplier_product_code: nil) }
    let!(:catalog_item) { create(:supplier_catalog_item, product: product, barcode: "4904810950783", supplier_product_code: "TKT95078") }

    it "syncs selected fields" do
      post sync_fields_admin_catalog_review_path, params: {
        product_id: product.id,
        sync_fields: %w[barcode supplier_product_code],
        index: 0, modes: ["missing_data"]
      }

      expect(response).to have_http_status(:redirect)
      product.reload
      expect(product.barcode).to eq("4904810950783")
      expect(product.supplier_product_code).to eq("TKT95078")
    end

    it "does not sync without catalog link" do
      catalog_item.update!(product_id: nil)
      post sync_fields_admin_catalog_review_path, params: {
        product_id: product.id,
        sync_fields: %w[barcode],
        index: 0, modes: ["missing_data"]
      }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("no está vinculado")
    end
  end

  describe "PATCH /admin/catalog_review/update_name" do
    let!(:product) { create(:product, skip_seed_inventory: true, product_name: "Old Name") }

    it "updates the product name" do
      patch update_name_admin_catalog_review_path, params: {
        product_id: product.id,
        product_name: "New Better Name",
        index: 0, modes: ["low_similarity"]
      }

      expect(response).to have_http_status(:redirect)
      expect(product.reload.product_name).to eq("New Better Name")
    end
  end

  describe "POST /admin/catalog_review/mark_reviewed" do
    let!(:product) { create(:product, skip_seed_inventory: true) }

    it "creates a review record" do
      expect {
        post mark_reviewed_admin_catalog_review_path, params: {
          product_id: product.id,
          modes: ["unlinked"],
          index: 0
        }
      }.to change(ProductCatalogReview, :count).by(1)

      review = ProductCatalogReview.last
      expect(review.product_id).to eq(product.id)
      expect(review.reviewed_by_id).to eq(admin.id)
      expect(review.review_mode).to eq("unlinked")
    end

    it "does not create duplicate review" do
      create(:product_catalog_review, product: product)

      expect {
        post mark_reviewed_admin_catalog_review_path, params: {
          product_id: product.id,
          modes: ["unlinked"],
          index: 0
        }
      }.not_to change(ProductCatalogReview, :count)
    end
  end

  describe "POST /admin/catalog_review/unmark_reviewed" do
    let!(:product) { create(:product, skip_seed_inventory: true) }
    let!(:review) { create(:product_catalog_review, product: product) }

    it "destroys the review record" do
      expect {
        post unmark_reviewed_admin_catalog_review_path, params: {
          product_id: product.id,
          index: 0, modes: ["unlinked"]
        }
      }.to change(ProductCatalogReview, :count).by(-1)
    end
  end

  describe "authentication" do
    it "redirects unauthenticated users" do
      logout
      get admin_catalog_review_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects non-admin users" do
      logout
      customer = create(:user, role: :customer)
      login_as(customer, scope: :user)
      get admin_catalog_review_path
      expect(response).to redirect_to(root_path)
    end
  end
end
