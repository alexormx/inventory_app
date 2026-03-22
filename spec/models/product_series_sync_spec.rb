# frozen_string_literal: true

require "rails_helper"

RSpec.describe Product, type: :model do
  describe "series sync" do
    it "fills series from custom_attributes['series'] when series is blank" do
      product = build(:product, skip_seed_inventory: true, series: nil, custom_attributes: { "series" => "Tomica Premium" })

      product.valid?

      expect(product.series).to eq("Tomica Premium")
    end

    it "does not overwrite an existing persisted series" do
      product = build(:product, skip_seed_inventory: true, series: "Limited Vintage Neo", custom_attributes: { "series" => "Tomica Premium" })

      product.valid?

      expect(product.series).to eq("Limited Vintage Neo")
    end
  end
end