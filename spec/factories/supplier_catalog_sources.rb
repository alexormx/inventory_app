# frozen_string_literal: true

FactoryBot.define do
  factory :supplier_catalog_source do
    association :supplier_catalog_item
    source { "hlj" }
    external_id { supplier_catalog_item.external_sku }
    source_url { supplier_catalog_item.source_url }
    fetch_status { "ok" }
    image_urls { supplier_catalog_item.image_urls }
    normalized_payload { { "stock_status_raw" => "Future Release", "stock_status_normalized" => "future_release" } }
    raw_payload { { "stock_status_raw" => "Future Release" } }
    metadata { { "barcode" => supplier_catalog_item.barcode } }
    content_checksum { SecureRandom.hex(8) }
    last_seen_at { Time.current }
    last_changed_at { Time.current }
  end
end