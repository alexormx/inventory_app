# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Catalog::SyncProductService do
  describe "#call" do
    it "creates a draft product from an unlinked catalog item" do
      catalog_item = create(:supplier_catalog_item, product: nil)

      result = described_class.new(catalog_item).call

      expect(result.created).to be true
      expect(result.product).to be_persisted
      expect(result.product.product_sku).to eq(catalog_item.external_sku)
      expect(result.product.status).to eq("draft")
      expect(catalog_item.reload.product).to eq(result.product)
      expect(result.product.parsed_custom_attributes.dig("supplier_catalog", "external_sku")).to eq(catalog_item.external_sku)
    end

    it "links to an existing product by barcode" do
      product = create(:product, skip_seed_inventory: true, barcode: "4904810950783", supplier_product_code: nil)
      catalog_item = create(:supplier_catalog_item, product: nil, barcode: "4904810950783", supplier_product_code: "TKT95078")

      result = described_class.new(catalog_item).call

      expect(result.created).to be false
      expect(result.product).to eq(product)
      expect(product.reload.supplier_product_code).to eq("TKT95078")
      expect(catalog_item.reload.product).to eq(product)
    end
  end
end