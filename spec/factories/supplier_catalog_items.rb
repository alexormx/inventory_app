# frozen_string_literal: true

FactoryBot.define do
  sequence(:supplier_catalog_external_sku) { |n| "HLJ-#{n.to_s.rjust(5, '0')}" }

  factory :supplier_catalog_item do
    source_key { "hlj" }
    external_sku { generate(:supplier_catalog_external_sku) }
    barcode { "4904810950783" }
    supplier_product_code { "TKT95078" }
    canonical_name { "No.43 Lamborghini Temerario" }
    canonical_brand { "Takara Tomy" }
    canonical_category { "Cars & Bikes" }
    canonical_series { "Tomica" }
    canonical_item_type { "Toys" }
    canonical_release_date { Date.new(2026, 2, 21) }
    canonical_price { 74.29 }
    currency { "MXN" }
    canonical_status { "future_release" }
    source_url { "https://www.hlj.com/no-43-lamborghini-temerario-tkt95078" }
    main_image_url { "https://www.hlj.com/productimages/tkt/tkt95078_0.jpg" }
    image_urls { ["https://www.hlj.com/productimages/tkt/tkt95078_0.jpg"] }
    description_raw { "This is a completed toy designed for children and/or collectors." }
    details_payload { { "series" => "Tomica", "item_type" => "Toys" } }
    raw_payload { { "stock_status_raw" => "Future Release" } }
    last_seen_at { Time.current }
    last_status_change_at { Time.current }
  end
end