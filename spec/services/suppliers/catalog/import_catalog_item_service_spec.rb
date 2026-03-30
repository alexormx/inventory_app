# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Catalog::ImportCatalogItemService do
  subject(:service) do
    described_class.new(
      source: "hlj",
      external_sku: "TKT95078",
      name: "No.43 Lamborghini Temerario",
      source_url: "https://www.hlj.com/no-43-lamborghini-temerario-tkt95078",
      raw_status: raw_status,
      barcode: "4904810950783",
      supplier_product_code: "TKT95078",
      canonical_brand: "Takara Tomy",
      canonical_category: "Cars & Bikes",
      canonical_series: "Tomica",
      canonical_item_type: "Toys",
      canonical_release_date: Date.new(2026, 2, 21),
      canonical_price: 74.29,
      description_raw: "This is a completed toy designed for children and/or collectors.",
      image_urls: ["https://www.hlj.com/productimages/tkt/tkt95078_0.jpg"],
      normalized_payload: { "series" => "Tomica", "item_type" => "Toys" },
      raw_payload: { "stock_status_raw" => raw_status }
    )
  end

  let(:raw_status) { "Future Release" }

  it "creates a catalog item and source snapshot" do
    result = service.call

    expect(result.created).to be true
    expect(result.catalog_item.canonical_status).to eq("future_release")
    expect(result.catalog_item.barcode).to eq("4904810950783")
    expect(result.catalog_source.source).to eq("hlj")
    expect(result.catalog_source.fetch_status).to eq("ok")
  end

  it "updates status change timestamps when status changes" do
    first_result = service.call
    original_changed_at = first_result.catalog_item.last_status_change_at

    travel 1.minute do
      updated = described_class.new(
        source: "hlj",
        external_sku: "TKT95078",
        name: "No.43 Lamborghini Temerario",
        source_url: "https://www.hlj.com/no-43-lamborghini-temerario-tkt95078",
        raw_status: "In Stock",
        barcode: "4904810950783",
        supplier_product_code: "TKT95078",
        canonical_brand: "Takara Tomy",
        canonical_category: "Cars & Bikes",
        normalized_payload: { "series" => "Tomica" },
        raw_payload: { "stock_status_raw" => "In Stock" }
      ).call

      expect(updated.status_changed).to be true
      expect(updated.catalog_item.reload.canonical_status).to eq("in_stock")
      expect(updated.catalog_item.last_status_change_at).to be > original_changed_at
    end
  end

  it "marks recent additions for review when requested" do
    result = described_class.new(
      source: "hlj",
      external_sku: "TKT95079",
      name: "No.44 Nissan GT-R",
      source_url: "https://www.hlj.com/no-44-nissan-gt-r-tkt95079",
      raw_status: "Future Release",
      review_feed: "recent_additions",
      normalized_payload: { "series" => "Tomica" },
      raw_payload: { "stock_status_raw" => "Future Release" }
    ).call

    expect(result.catalog_item.last_hlj_recent_added_at).to be_present
    expect(result.catalog_item.last_hlj_recent_arrival_at).to be_nil
    expect(result.catalog_item.needs_review).to be true
  end

  it "marks recent arrivals for review when requested" do
    result = described_class.new(
      source: "hlj",
      external_sku: "TKT95080",
      name: "No.45 Toyota GR86",
      source_url: "https://www.hlj.com/no-45-toyota-gr86-tkt95080",
      raw_status: "In Stock",
      review_feed: "recent_arrivals",
      normalized_payload: { "series" => "Tomica" },
      raw_payload: { "stock_status_raw" => "In Stock" }
    ).call

    expect(result.catalog_item.last_hlj_recent_arrival_at).to be_present
    expect(result.catalog_item.last_hlj_recent_added_at).to be_nil
    expect(result.catalog_item.canonical_status).to eq("in_stock")
  end
end