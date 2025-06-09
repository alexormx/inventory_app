FactoryBot.define do
  factory :product do
    sequence(:product_name) { |n| "Product #{n}" }
    sequence(:product_sku) { |n| "SKU#{n}" }

    selling_price { 100.0 }
    minimum_price { 80.0 }
    maximum_discount { 20.0 }

    discount_limited_stock { 10 }
    reorder_point { 20 }

    brand { "BrandName" }
    category { "CategoryName" }

    length_cm { 10 }
    width_cm { 5 }
    height_cm { 3 }
    weight_gr { 1.2 }

    backorder_allowed { false }
    preorder_available { false }

    custom_attributes { nil }

    status { "active" }
  end
end

