# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Hlj::DiscoveryService do
  let(:connection) { instance_double(Faraday::Connection) }

  let(:list_html) do
    <<~HTML
      <html>
        <ul class="pages"><li>1</li><li>2</li><li>Next</li></ul>
        <div class="search-widget-block">
          <a href="/no-43-lamborghini-temerario-tkt95078"></a>
          <div class="product-item-name">No.43 Lamborghini Temerario</div>
          <div class="price"><span id="TKT95078_price"></span>$74.29 MXN</div>
        </div>
      </html>
    HTML
  end

  let(:detail_html) do
    <<~HTML
      <html>
        <body>
          <h1>No.43 Lamborghini Temerario</h1>
          <div class="product-stock">Future Release</div>
          <p class="price">$74.29 MXN</p>
          <h3>Description</h3>
          <p>This is a completed toy designed for children and/or collectors.</p>
          <div class="fotorama"><a href="https://www.hlj.com/productimages/tkt/tkt95078_0.jpg">img</a></div>
          <div class="product-details"><ul><li>Code: TKT95078</li><li>JAN Code: 4904810950783</li><li>Manufacturer: Takara Tomy</li><li>Series: Tomica</li></ul></div>
        </body>
      </html>
    HTML
  end

  before do
    allow(connection).to receive(:get) do |url, &_block|
      body = url.include?("Page=") || url == described_class::SEARCH_URL ? list_html : detail_html
      instance_double(Faraday::Response, success?: true, status: 200, body: body)
    end
  end

  it "imports catalog items from the listing and records the run" do
    expect do
      described_class.new(max_pages: 1, connection: connection).call
    end.to change(SupplierCatalogItem, :count).by(1)
      .and change(SupplierCatalogSource, :count).by(1)
      .and change(SupplierSyncRun, :count).by(1)

    item = SupplierCatalogItem.last
    run = SupplierSyncRun.last

    expect(item.external_sku).to eq("TKT95078")
    expect(item.canonical_status).to eq("future_release")
    expect(run.status).to eq("completed")
    expect(run.processed_count).to eq(1)
  end
end