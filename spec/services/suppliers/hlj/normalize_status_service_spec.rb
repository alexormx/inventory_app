# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Hlj::NormalizeStatusService do
  describe "#call" do
    it "maps known availability text" do
      expect(described_class.new("In Stock").call).to eq("in_stock")
      expect(described_class.new("Future Release").call).to eq("future_release")
      expect(described_class.new("Order Stop").call).to eq("order_stop")
    end

    # HLJ separa las palabras con U+00A0, que \s no captura en Ruby.
    it "maps availability text separated by non-breaking spaces" do
      expect(described_class.new("In\u00A0Stock").call).to eq("in_stock")
      expect(described_class.new("Aug\u00A0\u00A0Release").call).to eq("aug_release")
    end

    it "returns nil for blank input" do
      expect(described_class.new(nil).call).to be_nil
      expect(described_class.new("   ").call).to be_nil
    end

    it "keeps the granularity of texts without an explicit mapping" do
      expect(described_class.new("In Stock 5-7 Days").call).to eq("in_stock_5_7_days")
    end
  end

  describe ".from_live_price" do
    it "prefers the availability text over the stock status code" do
      status = described_class.from_live_price(availability: "Oct Release", stock_status_code: "futurerelease")

      expect(status).to eq("oct_release")
    end

    it "falls back to known stock status codes" do
      expect(described_class.from_live_price(stock_status_code: "instock")).to eq("in_stock")
      expect(described_class.from_live_price(stock_status_code: "outofstock")).to eq("out_of_stock")
      expect(described_class.from_live_price(stock_status_code: "backorder")).to eq("backordered")
    end

    it "returns nil and logs when the stock status code is unknown" do
      logger = instance_double(Logger)
      allow(logger).to receive(:warn)

      status = described_class.from_live_price(stock_status_code: "brandnewcode", logger: logger)

      expect(status).to be_nil
      expect(logger).to have_received(:warn).with(/brandnewcode/)
    end

    it "returns nil when the supplier reports nothing, so callers keep the current status" do
      expect(described_class.from_live_price(availability: nil, stock_status_code: nil)).to be_nil
      expect(described_class.from_live_price(availability: "", stock_status_code: "  ")).to be_nil
    end
  end
end
