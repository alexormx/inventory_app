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
          <img src="//www.hlj.com/productimages/tkt/tkt95078_0.jpg">
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
    allow(Kernel).to receive(:sleep)

    allow(connection).to receive(:get) do |url, &_block|
      body = url.start_with?(described_class::SEARCH_URL) ? list_html : detail_html
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

  it "falls back to the listing title when the detail page is blocked" do
    allow(connection).to receive(:get) do |url, &_block|
      body = if url.start_with?(described_class::SEARCH_URL)
               list_html
             else
               <<~HTML
                 <html>
                   <head><title>Human Verification</title></head>
                   <body><h1>JavaScript is disabled</h1></body>
                 </html>
               HTML
             end
      instance_double(Faraday::Response, success?: true, status: 200, body: body)
    end

    described_class.new(max_pages: 1, connection: connection).call

    item = SupplierCatalogItem.last
    expect(item.canonical_name).to eq("No.43 Lamborghini Temerario")
    expect(item.main_image_url).to eq("https://www.hlj.com/productimages/tkt/tkt95078_0.jpg")
  end

  it "cancels the run when a stop is requested" do
    run = create(:supplier_sync_run, source: "hlj", mode: "weekly_discovery", status: "queued")

    allow(connection).to receive(:get) do |url, &_block|
      if url.start_with?(described_class::SEARCH_URL)
        run.start! if run.reload.status == "queued"
        run.request_stop!
        instance_double(Faraday::Response, success?: true, status: 200, body: list_html)
      else
        instance_double(Faraday::Response, success?: true, status: 200, body: detail_html)
      end
    end

    described_class.new(max_pages: 1, connection: connection, run: run).call

    expect(run.reload.status).to eq("cancelled")
    expect(run.metadata["stop_requested"]).to be true
    expect(run.metadata["cancelled_by_user"]).to be true
    expect(SupplierCatalogItem.count).to eq(0)
  end

  it "stops after reaching the configured max_items" do
    multi_list_html = <<~HTML
      <html>
        <ul class="pages"><li>1</li><li>1</li><li>Next</li></ul>
        <div class="search-widget-block">
          <a href="/item-1-tkt95078"></a>
          <img src="//www.hlj.com/productimages/tkt/tkt95078_0.jpg">
          <div class="product-item-name">No.43 Lamborghini Temerario</div>
          <div class="price"><span id="TKT95078_price"></span>$74.29 MXN</div>
        </div>
        <div class="search-widget-block">
          <a href="/item-2-tkt95079"></a>
          <img src="//www.hlj.com/productimages/tkt/tkt95079_0.jpg">
          <div class="product-item-name">No.44 Nissan GT-R</div>
          <div class="price"><span id="TKT95079_price"></span>$70.00 MXN</div>
        </div>
      </html>
    HTML

    allow(connection).to receive(:get) do |url, &_block|
      body = url.start_with?(described_class::SEARCH_URL) ? multi_list_html : detail_html
      instance_double(Faraday::Response, success?: true, status: 200, body: body)
    end

    described_class.new(max_pages: 1, max_items: 1, fetch_detail: false, connection: connection).call

    expect(SupplierCatalogItem.count).to eq(1)
    expect(SupplierSyncRun.last.processed_count).to eq(1)
  end

  it "builds filtered HLJ listing URLs from discovery options" do
    requested_urls = []

    allow(connection).to receive(:get) do |url, &_block|
      requested_urls << url
      body = url.start_with?(described_class::SEARCH_URL) ? list_html : detail_html
      instance_double(Faraday::Response, success?: true, status: 200, body: body)
    end

    described_class.new(
      max_pages: 1,
      word: "tomica",
      makers: ["Takara Tomy", "Tomy", "Tomytec"],
      genre_codes: ["Cars & Bikes"],
      fetch_detail: false,
      connection: connection
    ).call

    listing_url = requested_urls.find { |url| url.start_with?(described_class::SEARCH_URL) }

    expect(listing_url).to include("Word=tomica")
    expect(listing_url).to include("Maker2=Takara+Tomy")
    expect(listing_url).to include("Maker2=Tomy")
    expect(listing_url).to include("Maker2=Tomytec")
    expect(listing_url).to include("GenreCode2=Cars+%26+Bikes")
  end

  it "tracks recent additions timestamps when review feed is recent_additions" do
    described_class.new(max_pages: 1, fetch_detail: false, review_feed: "recent_additions", connection: connection).call

    item = SupplierCatalogItem.last
    expect(item.last_hlj_recent_added_at).to be_present
    expect(item.last_hlj_recent_arrival_at).to be_nil
  end

  it "tracks recent arrivals timestamps when review feed is recent_arrivals" do
    described_class.new(max_pages: 1, fetch_detail: false, review_feed: "recent_arrivals", connection: connection).call

    item = SupplierCatalogItem.last
    expect(item.last_hlj_recent_arrival_at).to be_present
    expect(item.last_hlj_recent_added_at).to be_nil
  end

  it "builds HLJ listing URLs with date filters" do
    requested_urls = []

    allow(connection).to receive(:get) do |url, &_block|
      requested_urls << url
      body = url.start_with?(described_class::SEARCH_URL) ? list_html : detail_html
      instance_double(Faraday::Response, success?: true, status: 200, body: body)
    end

    described_class.new(
      max_pages: 1,
      word: "tomica",
      date_added_within_days: 10,
      date_arrivals_within_days: 10,
      fetch_detail: false,
      connection: connection
    ).call

    listing_url = requested_urls.find { |url| url.start_with?(described_class::SEARCH_URL) }
    expect(listing_url).to include("dateAdded2=-10")
    expect(listing_url).to include("dateArrivals=-10")
  end
end