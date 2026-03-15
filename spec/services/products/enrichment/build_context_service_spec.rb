# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::Enrichment::BuildContextService do
  let(:product) { create(:product, skip_seed_inventory: true, brand: "Tomica", category: "diecast", description: "Existing desc", selling_price: 199.99, barcode: "1234567890", supplier_product_code: "SUP-001", launch_date: Date.new(2024, 3, 1), weight_gr: 100, length_cm: 16, width_cm: 4, height_cm: 4) }

  subject(:context) { described_class.new(product).call }

  it "returns a hash with product data" do
    expect(context).to be_a(Hash)
    expect(context[:product_id]).to eq(product.id)
    expect(context[:product_sku]).to eq(product.product_sku)
    expect(context[:product_name]).to eq(product.product_name)
    expect(context[:brand]).to eq("Tomica")
    expect(context[:category]).to eq("diecast")
    expect(context[:description]).to eq("Existing desc")
    expect(context[:selling_price]).to eq(199.99)
  end

  it "includes dimensions" do
    dims = context[:dimensions]
    expect(dims[:weight_gr]).to eq(100.0)
    expect(dims[:length_cm]).to eq(16.0)
    expect(dims[:width_cm]).to eq(4.0)
    expect(dims[:height_cm]).to eq(4.0)
  end

  it "includes identifiers" do
    expect(context[:barcode]).to eq("1234567890")
    expect(context[:supplier_code]).to eq("SUP-001")
    expect(context[:launch_date]).to eq("2024-03-01")
  end

  context "with a category attribute template" do
    let!(:template) { create(:category_attribute_template, category: "diecast") }

    it "includes template context" do
      tmpl = context[:template]
      expect(tmpl).to be_present
      expect(tmpl[:category]).to eq("diecast")
      expect(tmpl[:keys]).to include("color", "escala")
      expect(tmpl[:required]).to include("color")
      expect(tmpl[:schema]).to be_an(Array)
    end
  end

  context "without a category attribute template" do
    it "returns nil for template" do
      expect(context[:template]).to be_nil
    end
  end
end
