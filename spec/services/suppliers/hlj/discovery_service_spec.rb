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

  describe "incremental sync" do
    let(:live_entries) { {} }
    let(:failed_skus) { [] }
    let(:live_price_service) do
      result = Suppliers::Hlj::LivePriceService::Result.new(prices: live_entries, failed_skus: failed_skus)
      instance_double(Suppliers::Hlj::LivePriceService, call: result)
    end
    let(:requested_urls) { [] }
    let(:total_pages_reported) { 2 }

    def paged_list_html(pages)
      list_html.sub('<ul class="pages"><li>1</li><li>2</li><li>Next</li></ul>',
                    %(<ul class="pages"><li>1</li><li>#{pages}</li><li>Next</li></ul>))
    end

    before do
      allow(connection).to receive(:get) do |url, &_block|
        requested_urls << url
        body = url.start_with?(described_class::SEARCH_URL) ? paged_list_html(total_pages_reported) : detail_html
        instance_double(Faraday::Response, success?: true, status: 200, body: body)
      end
    end

    def detail_requests
      requested_urls.reject { |url| url.start_with?(described_class::SEARCH_URL) }
    end

    def run_discovery(**options)
      described_class.new(connection: connection, live_price_service: live_price_service, **options).call
    end

    it "downloads the detail page for a SKU it has never seen" do
      run_discovery(max_pages: 1, detail_policy: "new_only")

      expect(detail_requests.size).to eq(1)
      expect(SupplierCatalogItem.find_by(external_sku: "TKT95078").last_full_sync_at).to be_present
    end

    it "does not download the detail page for a SKU that already exists" do
      create(:supplier_catalog_item, external_sku: "TKT95078", canonical_status: "in_stock")

      run_discovery(max_pages: 1, detail_policy: "new_only")

      expect(detail_requests).to be_empty
    end

    it "still downloads every detail page when the policy is all" do
      create(:supplier_catalog_item, external_sku: "TKT95078", canonical_status: "in_stock")

      run_discovery(max_pages: 1, detail_policy: "all")

      expect(detail_requests.size).to eq(1)
    end

    it "counts an existing item with no changes as unchanged, not updated" do
      create(:supplier_catalog_item, external_sku: "TKT95078", canonical_status: "in_stock")

      run_discovery(max_pages: 1, detail_policy: "new_only")
      run = SupplierSyncRun.last

      expect(run.processed_count).to eq(1)
      expect(run.created_count).to eq(0)
      expect(run.updated_count).to eq(0)
      expect(run.metadata["unchanged_count"]).to eq(1)
    end

    context "when the supplier reports a new status" do
      let(:live_entries) { { "TKT95078" => { "availability" => "Sold Out" } } }

      it "counts the item as updated" do
        create(:supplier_catalog_item, external_sku: "TKT95078", canonical_status: "in_stock")

        run_discovery(max_pages: 1, detail_policy: "new_only")
        run = SupplierSyncRun.last

        expect(run.updated_count).to eq(1)
        expect(run.metadata["status_changed_count"]).to eq(1)
        expect(SupplierCatalogItem.find_by(external_sku: "TKT95078").canonical_status).to eq("sold_out")
      end
    end

    it "does not flag an unchanged item for review even on a review feed" do
      item = create(:supplier_catalog_item, external_sku: "TKT95078", canonical_status: "in_stock",
                                            needs_review: false)

      run_discovery(max_pages: 1, detail_policy: "new_only", review_feed: "recent_arrivals")

      expect(item.reload.needs_review).to be false
      expect(item.last_hlj_recent_arrival_at).to be_present
    end

    it "keeps existing data when livePrice returns nothing for the SKU" do
      item = create(:supplier_catalog_item, external_sku: "TKT95078", canonical_status: "in_stock",
                                            canonical_price: BigDecimal("1000"), currency: "JPY")

      run_discovery(max_pages: 1, detail_policy: "new_only")

      item.reload
      expect(item.canonical_status).to eq("in_stock")
      expect(item.canonical_price).to eq(BigDecimal("1000"))
      expect(item.canonical_name).to eq("No.43 Lamborghini Temerario")
      expect(item.description_raw).to be_present
    end

    it "does not stamp last_full_sync_at when no detail page was downloaded" do
      item = create(:supplier_catalog_item, external_sku: "TKT95078", last_full_sync_at: nil)

      run_discovery(max_pages: 1, detail_policy: "new_only")

      expect(item.reload.last_full_sync_at).to be_nil
    end

    it "looks up existing SKUs with a single query per page" do
      create(:supplier_catalog_item, external_sku: "TKT95078")
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        queries << payload[:sql] if payload[:sql].include?('FROM "supplier_catalog_items"')
      end

      begin
        run_discovery(max_pages: 1, detail_policy: "new_only")
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      lookups = queries.count { |sql| sql.include?("external_sku") }
      expect(lookups).to eq(1)
    end

    context "when HLJ reports far more pages than expected" do
      let(:total_pages_reported) { 240 }

      it "traverses only max_pages and records the anomaly" do
        run_discovery(max_pages: 2, detail_policy: "new_only")

        listing_requests = requested_urls.count { |url| url.start_with?(described_class::SEARCH_URL) }
        run = SupplierSyncRun.last

        expect(listing_requests).to eq(2)
        expect(run.metadata["page_count_anomaly"]).to be true
        expect(run.metadata["remote_total_pages"]).to eq(240)
        expect(run.metadata["pages_traversed"]).to eq(2)
        expect(run.metadata["max_pages"]).to eq(2)
      end
    end

    it "records the detail policy and the configured limits in the run metadata" do
      run_discovery(max_pages: 1, max_items: 1, detail_policy: "new_only")
      run = SupplierSyncRun.last

      expect(run.metadata["detail_policy"]).to eq("new_only")
      expect(run.metadata["max_items"]).to eq(1)
      expect(run.metadata["detail_fetch_count"]).to eq(1)
    end

    # Última red de seguridad si los límites por página fallan: la corrida se
    # corta por reloj y lo deja registrado en vez de seguir horas.
    it "stops on the wall-clock budget and records why" do
      started = Time.current
      allow(Time).to receive(:current).and_return(started, started, started + 2.hours)

      run_discovery(max_pages: 2, detail_policy: "new_only", max_duration_seconds: 60)
      run = SupplierSyncRun.last

      expect(run.metadata["stopped_reason"]).to eq("max_duration_seconds")
      expect(run.status).to eq("completed")
    end

    it "logs a per-item failure instead of aborting the run" do
      allow(Suppliers::Catalog::ImportCatalogItemService).to receive(:new).and_raise(StandardError, "boom")

      run_discovery(max_pages: 1, detail_policy: "new_only")
      run = SupplierSyncRun.last

      expect(run.status).to eq("completed")
      expect(run.skipped_count).to eq(1)
      expect(run.error_samples.first).to include("TKT95078", "boom")
    end
  end
end