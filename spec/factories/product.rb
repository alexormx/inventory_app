FactoryBot.define do
  factory :product do
    sequence(:product_name) { |n| "Product #{n}" }
    sequence(:product_sku) { |n| "SKU#{n}" }

    selling_price { 100.0 }
    minimum_price { 80.0 }  # debe ser ≤ selling_price
    maximum_discount { 20.0 }

    discount_limited_stock { 10 }

    # Opcional para que se vea completo, no es requerido por validaciones
    stock_quantity { 100 }
    reserved_quantity { 10 }
    reorder_point { 20 }
    backorder_allowed { false }
    preorder_available { false }
    custom_attributes { { color: "red", size: "M" } }
    barcode { "1234567890123" }
    brand { "BrandName" }
    category { "CategoryName" }
    
    
    length_cm { 10 }
    width_cm { 5 }
    height_cm { 3 }
    weight_gr { 1.2 }

    status { "active" }
  end
end
