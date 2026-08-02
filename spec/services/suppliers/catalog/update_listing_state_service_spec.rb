# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Catalog::UpdateListingStateService do
  let(:catalog_item) do
    create(:supplier_catalog_item,
           canonical_status: "in_stock",
           canonical_price: BigDecimal("1000"),
           currency: "JPY",
           needs_review: false)
  end

  it "updates only the status when the price is unchanged" do
    result = described_class.new(catalog_item: catalog_item, status: "sold_out").call

    expect(result.status_changed).to be true
    expect(result.price_changed).to be false
    expect(result.changed).to be true
    expect(catalog_item.reload.canonical_status).to eq("sold_out")
  end

  it "updates only the price when the status is unchanged" do
    result = described_class.new(catalog_item: catalog_item, status: "in_stock", price: "1500", currency: "JPY").call

    expect(result.status_changed).to be false
    expect(result.price_changed).to be true
    expect(catalog_item.reload.canonical_price).to eq(BigDecimal("1500"))
  end

  it "reports no change and writes nothing when status and price are identical" do
    expect do
      result = described_class.new(catalog_item: catalog_item, status: "in_stock", price: "1000",
                                   currency: "JPY", touch_timestamps: false).call
      expect(result.changed).to be false
    end.not_to change { catalog_item.reload.updated_at }
  end

  it "never overwrites descriptive fields captured by a full sync" do
    described_class.new(catalog_item: catalog_item, status: "sold_out", price: "1500", currency: "JPY").call
    catalog_item.reload

    expect(catalog_item.canonical_name).to eq("No.43 Lamborghini Temerario")
    expect(catalog_item.description_raw).to be_present
    expect(catalog_item.image_urls).to be_present
    expect(catalog_item.main_image_url).to be_present
    expect(catalog_item.details_payload).to eq("series" => "Tomica", "item_type" => "Toys")
    expect(catalog_item.last_full_sync_at).to be_nil
  end

  it "keeps the current status when the supplier reports nothing" do
    described_class.new(catalog_item: catalog_item, status: nil).call

    expect(catalog_item.reload.canonical_status).to eq("in_stock")
  end

  it "keeps the current price when the supplier reports nothing" do
    described_class.new(catalog_item: catalog_item, price: nil).call

    expect(catalog_item.reload.canonical_price).to eq(BigDecimal("1000"))
  end

  it "ignores a negative price instead of storing it" do
    result = described_class.new(catalog_item: catalog_item, price: "-5").call

    expect(result.price_changed).to be false
    expect(catalog_item.reload.canonical_price).to eq(BigDecimal("1000"))
  end

  it "flags a review-feed item for review only when something actually changed" do
    described_class.new(catalog_item: catalog_item, status: "in_stock", review_feed: "recent_arrivals").call
    expect(catalog_item.reload.needs_review).to be false

    described_class.new(catalog_item: catalog_item, status: "sold_out", review_feed: "recent_arrivals").call
    expect(catalog_item.reload.needs_review).to be true
  end

  it "records the review-feed timestamp even when nothing changed" do
    described_class.new(catalog_item: catalog_item, status: "in_stock", review_feed: "recent_additions").call

    expect(catalog_item.reload.last_hlj_recent_added_at).to be_present
  end

  it "leaves the seen timestamps untouched when the caller batches them" do
    catalog_item.update_columns(last_seen_at: 3.days.ago, source_last_synced_at: 3.days.ago)
    previous = catalog_item.reload.last_seen_at

    described_class.new(catalog_item: catalog_item, status: "sold_out", touch_timestamps: false).call

    expect(catalog_item.reload.last_seen_at).to be_within(1.second).of(previous)
  end
end
