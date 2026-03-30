# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Hlj::SearchQuery do
  it "builds a search URL with added and arrivals windows" do
    url = described_class.new(
      word: "tomica",
      makers: ["Takara Tomy"],
      date_added_within_days: 10,
      date_arrivals_within_days: 10
    ).page_url(2)

    expect(url).to include("Word=tomica")
    expect(url).to include("Maker2=Takara+Tomy")
    expect(url).to include("dateAdded2=-10")
    expect(url).to include("dateArrivals=-10")
    expect(url).to include("Page=2")
  end

  it "omits date filters when no positive values are provided" do
    url = described_class.new(word: "tomica", date_added_within_days: 0, date_arrivals_within_days: nil).page_url

    expect(url).to include("Word=tomica")
    expect(url).not_to include("dateAdded2")
    expect(url).not_to include("dateArrivals")
  end
end