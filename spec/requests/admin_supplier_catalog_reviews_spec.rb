# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SupplierCatalogReviews", type: :request do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: :admin) }

  before { login_as(admin, scope: :user) }

  describe "GET /admin/supplier_catalog_review" do
    let!(:added_item) do
      create(:supplier_catalog_item,
             canonical_name: "Tomica Added",
             last_hlj_recent_added_at: 1.day.ago,
             last_hlj_recent_arrival_at: nil)
    end
    let!(:arrival_item) do
      create(:supplier_catalog_item,
             canonical_name: "Tomica Arrival",
             last_hlj_recent_added_at: nil,
             last_hlj_recent_arrival_at: 1.day.ago,
             canonical_status: "in_stock")
    end

    it "renders recent additions by default" do
      get admin_supplier_catalog_review_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Revisión Tomica HLJ")
      expect(response.body).to include("Tomica Added")
      expect(response.body).not_to include("Tomica Arrival")
    end

    it "renders recent arrivals when feed is selected" do
      get admin_supplier_catalog_review_path(feed: "recent_arrivals")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tomica Arrival")
      expect(response.body).to include("Arrivals HLJ")
    end

    it "renders feed options with internal values and human labels" do
      get admin_supplier_catalog_review_path(feed: "recent_arrivals")

      expect(response.body).to include('option selected="selected" value="recent_arrivals"')
      expect(response.body).to include('>Arrivals HLJ (10 días)</option>')
      expect(response.body).to include('value="recent_additions"')
    end

    it "excludes reviewed items for the selected feed by default" do
      create(:supplier_catalog_review, supplier_catalog_item: added_item, review_mode: "recent_additions")

      get admin_supplier_catalog_review_path(feed: "recent_additions")

      expect(response.body).not_to include("Tomica Added")
    end

    it "includes reviewed items when requested" do
      create(:supplier_catalog_review, supplier_catalog_item: added_item, review_mode: "recent_additions")

      get admin_supplier_catalog_review_path(feed: "recent_additions", show_reviewed: "1")

      expect(response.body).to include("Tomica Added")
      expect(response.body).to include("Revisado")
    end
  end

  describe "POST /admin/supplier_catalog_review/mark_reviewed" do
    let!(:item) { create(:supplier_catalog_item, last_hlj_recent_added_at: 1.day.ago) }

    it "creates a feed-specific review record" do
      expect do
        post mark_reviewed_admin_supplier_catalog_review_path, params: {
          supplier_catalog_item_id: item.id,
          feed: "recent_additions",
          index: 0
        }
      end.to change(SupplierCatalogReview, :count).by(1)

      review = SupplierCatalogReview.last
      expect(review.supplier_catalog_item).to eq(item)
      expect(review.review_mode).to eq("recent_additions")
      expect(review.reviewed_by).to eq(admin)
    end
  end

  describe "POST /admin/supplier_catalog_review/unmark_reviewed" do
    let!(:item) { create(:supplier_catalog_item, last_hlj_recent_arrival_at: 1.day.ago) }
    let!(:review) { create(:supplier_catalog_review, supplier_catalog_item: item, review_mode: "recent_arrivals") }

    it "removes the review for the selected feed" do
      expect do
        post unmark_reviewed_admin_supplier_catalog_review_path, params: {
          supplier_catalog_item_id: item.id,
          feed: "recent_arrivals",
          index: 0
        }
      end.to change(SupplierCatalogReview, :count).by(-1)
    end
  end
end