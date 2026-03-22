# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogHelper, type: :helper do
  describe "#product_breadcrumbs" do
    let(:product) do
      create(
        :product,
        skip_seed_inventory: true,
        category: "Limited Vintage",
        brand: "Tomica",
        product_name: "LV-N321a Nissan Truck 4X4 King Cab",
        status: "active"
      )
    end

    it "includes series between brand and product when supplier catalog series exists" do
      create(:supplier_catalog_item, product: product, canonical_series: "Tomica Limited Vintage")

      crumbs = helper.product_breadcrumbs(product)

      expect(crumbs.map { |crumb| crumb[:name] }).to eq([
        "Inicio",
        "Catálogo",
        "Limited Vintage",
        "Tomica",
        "Tomica Limited Vintage",
        "LV-N321a Nissan Truck 4X4 King Cab"
      ])
    end

    it "falls back to custom_attributes series when supplier catalog series is missing" do
      product.update!(custom_attributes: { "series" => "Tomica Premium" })

      crumbs = helper.product_breadcrumbs(product)

      expect(crumbs.map { |crumb| crumb[:name] }).to include("Tomica Premium")
    end
  end
end