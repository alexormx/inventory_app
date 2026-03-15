# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::TakaraTomyMall::BuildUrlService do
  it "builds the Takara Tomy Mall product URL from barcode" do
    url = described_class.new("4904810950783").call

    expect(url).to eq("https://takaratomymall.jp/shop/g/g4904810950783/")
  end

  it "returns nil for blank barcode" do
    expect(described_class.new(nil).call).to be_nil
  end
end