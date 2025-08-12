FactoryBot.define do
  sequence(:sku_seq)       { |n| "SKU-#{n.to_s.rjust(5, '0')}" }
  sequence(:whatsapp_seq)  { |n| "WGT#{n.to_s.rjust(3, '0')}" }

  factory :product do
    product_sku     { generate(:sku_seq) }
    product_name    { "Sample Product" }
    brand           { "Tomica" }

    # Category/status – safe defaults
    category        { "diecast" }
    status          { "draft" }

    # Prices & discounts – keep valid relationship
    minimum_price   { 99.99 }
    selling_price   { 199.99 }
    maximum_discount { 0 }            # ✅ required numeric

    # Inventory-ish
    reorder_point   { 0 }
    backorder_allowed   { false }
    preorder_available  { false }

    # Dimensions
    weight_gr       { 100 }
    length_cm       { 16 }
    width_cm        { 4 }
    height_cm       { 4 }

    # Identifiers
    whatsapp_code   { generate(:whatsapp_seq) }  # ✅ required & unique

    custom_attributes { {} }

    after(:build) do |p|
      p.category = p.category.to_s.downcase if p.respond_to?(:category=)
    end

    trait :cheap do
      minimum_price { 5.0 }
      selling_price { 10.0 }
      maximum_discount { 0 }
    end
  end
end
