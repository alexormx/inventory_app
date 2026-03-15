# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Hlj::PreviewDiscoveryService do
  let(:connection) { instance_double(Faraday::Connection) }

  let(:page_one_html) do
    <<~HTML
      <html>
        <ul class="pages"><li>1</li><li>3</li><li>Next</li></ul>
        <div class="search-widget-block">
          <a href="/item-1-tkt95078"></a>
          <img src="//www.hlj.com/productimages/tkt/tkt95078_0.jpg">
          <div class="product-item-name">No.43 Lamborghini Temerario</div>
          <div class="price"><span id="TKT95078_price"></span>$74.29 MXN</div>
        </div>
      </html>
    HTML
  end

  let(:page_two_html) do
    <<~HTML
      <html>
        <ul class="pages"><li>1</li><li>3</li><li>Next</li></ul>
        <div class="search-widget-block">
          <a href="/item-2-tkt95079"></a>
          <img src="//www.hlj.com/productimages/tkt/tkt95079_0.jpg">
          <div class="product-item-name">No.44 Nissan GT-R</div>
          <div class="price"><span id="TKT95079_price"></span>$70.00 MXN</div>
        </div>
      </html>
    HTML
  end

  it "returns preview counts and samples without persisting records" do
    requested_urls = []

    allow(connection).to receive(:get) do |url, &_block|
      requested_urls << url
      body = url.include?("Page=2") ? page_two_html : page_one_html
      instance_double(Faraday::Response, success?: true, status: 200, body: body)
    end

    result = nil

    expect do
      result = described_class.new(
        max_pages: 2,
        word: "tomica",
        makers: ["Takara Tomy"],
        genre_code: "Cars & Bikes",
        connection: connection
      ).call
    end.not_to change(SupplierCatalogItem, :count)

    expect(result.total_found).to eq(2)
    expect(result.sample_items.size).to eq(2)
    expect(result.scanned_pages).to eq(2)
    expect(result.available_pages).to eq(3)
    expect(requested_urls.first).to include("Word=tomica")
    expect(requested_urls.first).to include("Maker2=Takara+Tomy")
    expect(requested_urls.first).to include("GenreCode2=Cars+%26+Bikes")
  end
end