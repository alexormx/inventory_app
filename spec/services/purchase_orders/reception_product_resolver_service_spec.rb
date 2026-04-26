require "rails_helper"

RSpec.describe PurchaseOrders::ReceptionProductResolverService, type: :service do
  describe "#call" do
    it "returns the product matched by supplier_product_code" do
      product = create(:product, skip_seed_inventory: true, supplier_product_code: "TKT95078", product_name: "Tomica Premium Skyline")

      result = described_class.new("TKT95078", product_name: "Tomica Premium Skyline").call

      expect(result.product_match).to eq(product)
      expect(result.name_similarity).to be > 0.9
      expect(result.catalog_matches).to eq([])
    end

    it "returns catalog candidates when there is no product match" do
      catalog_item = create(:supplier_catalog_item, product: nil, supplier_product_code: "TKT95111")

      result = described_class.new("TKT95111").call

      expect(result.product_match).to be_nil
      expect(result.catalog_matches).to include(catalog_item)
    end

    it "does not auto-create or sync products" do
      create(:supplier_catalog_item, product: nil, supplier_product_code: "TKT95222")

      expect {
        described_class.new("TKT95222").call
      }.not_to change(Product, :count)
    end

    it "returns name candidates when there is no exact code match" do
      product = create(:product, skip_seed_inventory: true, supplier_product_code: "OTHER", product_name: "Tomica Premium Ferrari F40 Red")

      result = described_class.new("MISSING", product_name: "Tomica Premium Ferrari F40").call

      expect(result.product_match).to be_nil
      expect(result.name_candidates).to include(product)
    end
  end
end
