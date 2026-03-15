# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplierCatalogSource, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:supplier_catalog_item) }
  end

  describe "validations" do
    subject(:catalog_source) { build(:supplier_catalog_source) }

    it { is_expected.to validate_presence_of(:source) }
    it { is_expected.to validate_presence_of(:fetch_status) }
    it { is_expected.to validate_uniqueness_of(:source).scoped_to(:supplier_catalog_item_id) }
  end

  describe ".available" do
    let!(:available_source) { create(:supplier_catalog_source, fetch_status: "ok") }
    let!(:pending_source) { create(:supplier_catalog_source, source: "takaratomy_mall", fetch_status: "pending", supplier_catalog_item: available_source.supplier_catalog_item) }

    it "returns only successful sources" do
      expect(described_class.available).to include(available_source)
      expect(described_class.available).not_to include(pending_source)
    end
  end
end