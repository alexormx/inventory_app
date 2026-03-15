# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::TomicaFandom::BuildPageTitleService do
  it "normalizes tomica numbering in page title candidates" do
    catalog_item = build(:supplier_catalog_item, canonical_name: "No.43 Lamborghini Temerario")

    titles = described_class.new(catalog_item).call

    expect(titles).to include("No. 43 Lamborghini Temerario")
  end
end