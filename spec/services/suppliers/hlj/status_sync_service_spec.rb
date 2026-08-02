# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Hlj::StatusSyncService do
  let(:logger) { Logger.new(File::NULL) }

  def live_price_double(prices: {}, failed_skus: [])
    result = Suppliers::Hlj::LivePriceService::Result.new(prices: prices, failed_skus: failed_skus)
    instance_double(Suppliers::Hlj::LivePriceService, call: result)
  end

  it "updates status and price without downloading any product page" do
    item = create(:supplier_catalog_item, external_sku: "TKT1", canonical_status: "in_stock",
                                          canonical_price: BigDecimal("1000"), currency: "JPY")
    service = live_price_double(prices: {
                                  "TKT1" => { "availability" => "Sold Out", "JPYprice" => "1200" }
                                })

    described_class.new(live_price_service: service, logger: logger).call

    item.reload
    expect(item.canonical_status).to eq("sold_out")
    expect(item.canonical_price).to eq(BigDecimal("1200"))
  end

  it "counts unchanged items separately from updated ones" do
    create(:supplier_catalog_item, external_sku: "TKT1", canonical_status: "in_stock",
                                   canonical_price: BigDecimal("1000"), currency: "JPY")
    create(:supplier_catalog_item, external_sku: "TKT2", canonical_status: "in_stock",
                                   canonical_price: BigDecimal("1000"), currency: "JPY")
    service = live_price_double(prices: {
                                  "TKT1" => { "availability" => "In Stock", "JPYprice" => "1000" },
                                  "TKT2" => { "availability" => "Sold Out", "JPYprice" => "1000" }
                                })

    counts = described_class.new(live_price_service: service, logger: logger).call

    expect(counts[:processed]).to eq(2)
    expect(counts[:updated]).to eq(1)
    expect(counts[:unchanged]).to eq(1)
    expect(counts[:status_changed]).to eq(1)
    expect(counts[:price_changed]).to eq(0)
  end

  it "does not touch items missing from the response when a batch fails" do
    item = create(:supplier_catalog_item, external_sku: "TKT1", canonical_status: "in_stock",
                                          canonical_price: BigDecimal("1000"), currency: "JPY")
    service = live_price_double(prices: {}, failed_skus: ["TKT1"])

    counts = described_class.new(live_price_service: service, logger: logger).call

    item.reload
    expect(item.canonical_status).to eq("in_stock")
    expect(item.canonical_price).to eq(BigDecimal("1000"))
    expect(counts[:skipped]).to eq(1)
    expect(counts[:updated]).to eq(0)
  end

  it "records the run counters and metadata" do
    create(:supplier_catalog_item, external_sku: "TKT1", canonical_status: "in_stock")
    service = live_price_double(prices: { "TKT1" => { "availability" => "Sold Out" } })

    described_class.new(live_price_service: service, logger: logger).call
    run = SupplierSyncRun.last

    expect(run.status).to eq("completed")
    expect(run.processed_count).to eq(1)
    expect(run.updated_count).to eq(1)
    expect(run.metadata["status_changed_count"]).to eq(1)
    expect(run.metadata["unchanged_count"]).to eq(0)
  end

  it "asks livePrice once per database batch instead of once per product" do
    3.times { |i| create(:supplier_catalog_item, external_sku: "TKT#{i}") }
    service = live_price_double(prices: {})

    described_class.new(live_price_service: service, batch_size: 3, logger: logger).call

    expect(service).to have_received(:call).once
  end

  it "leaves descriptive fields alone" do
    item = create(:supplier_catalog_item, external_sku: "TKT1", canonical_status: "in_stock")
    service = live_price_double(prices: { "TKT1" => { "availability" => "Sold Out" } })

    described_class.new(live_price_service: service, logger: logger).call

    item.reload
    expect(item.canonical_name).to eq("No.43 Lamborghini Temerario")
    expect(item.description_raw).to be_present
    expect(item.details_payload).to be_present
    expect(item.last_full_sync_at).to be_nil
  end

  it "stops once max_items is reached" do
    3.times { |i| create(:supplier_catalog_item, external_sku: "TKT#{i}") }
    service = live_price_double(prices: {})

    counts = described_class.new(live_price_service: service, batch_size: 1, max_items: 2, logger: logger).call

    expect(counts[:processed]).to eq(2)
  end
end
