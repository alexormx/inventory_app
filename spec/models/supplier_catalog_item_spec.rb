# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplierCatalogItem, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:product).optional }
    it { is_expected.to have_many(:supplier_catalog_sources).dependent(:destroy) }
    it { is_expected.to have_many(:supplier_sync_runs).dependent(:nullify) }
  end

  describe "validations" do
    subject(:catalog_item) { build(:supplier_catalog_item) }

    it { is_expected.to validate_presence_of(:source_key) }
    it { is_expected.to validate_presence_of(:external_sku) }
    it { is_expected.to validate_presence_of(:canonical_name) }
    it { is_expected.to validate_uniqueness_of(:external_sku).scoped_to(:source_key) }
  end

  describe "scopes" do
    let!(:linked_item) do
      create(:supplier_catalog_item,
             product: create(:product, skip_seed_inventory: true),
             canonical_status: "in_stock",
             external_sku: "HLJ-LINKED",
             barcode: "4904810950777")
    end
    let!(:unlinked_item) { create(:supplier_catalog_item, external_sku: "HLJ-UNLINKED", barcode: "4904810950999") }
    let!(:future_release_item) { create(:supplier_catalog_item, external_sku: "HLJ-FUTURE", barcode: "4904810950888", canonical_status: "future_release") }

    it ".linked returns items associated to products" do
      expect(described_class.linked).to include(linked_item)
      expect(described_class.linked).not_to include(unlinked_item)
    end

    it ".future_release returns items waiting for release" do
      expect(described_class.future_release).to include(future_release_item)
      expect(described_class.future_release).not_to include(linked_item)
    end
  end

  describe "#linked?" do
    it "returns true when product is present" do
      item = build(:supplier_catalog_item, product: build(:product, skip_seed_inventory: true))
      expect(item.linked?).to be true
    end

    it "returns false when product is absent" do
      expect(build(:supplier_catalog_item, product: nil).linked?).to be false
    end
  end
end