require "rails_helper"

RSpec.describe PurchaseOrders::ReceptionProductResolverService, type: :service do
  describe "#call" do
    it "returns an existing product matched by supplier_product_code" do
      product = create(:product, skip_seed_inventory: true, supplier_product_code: "TKT95078")

      result = described_class.new("TKT95078").call

      expect(result.product).to eq(product)
      expect(result.source).to eq(:product)
    end

    it "creates and links a product from an existing supplier catalog item" do
      catalog_item = create(:supplier_catalog_item, product: nil, supplier_product_code: "TKT95111")

      expect {
        result = described_class.new("TKT95111", hlj_lookup: ->(_code) { nil }).call
        expect(result.source).to eq(:catalog)
        expect(result.catalog_item).to eq(catalog_item)
        expect(result.product).to be_present
      }.to change(Product, :count).by(1)
    end

    it "falls back to HLJ lookup when the code is missing locally" do
      catalog_item = build(:supplier_catalog_item, product: nil, supplier_product_code: "TKT95222")
      hlj_lookup = lambda do |_code|
        catalog_item.save!
        catalog_item
      end

      expect {
        result = described_class.new("TKT95222", hlj_lookup: hlj_lookup).call
        expect(result.source).to eq(:hlj)
        expect(result.product).to be_present
      }.to change(Product, :count).by(1)
    end
  end
end