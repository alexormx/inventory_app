FactoryBot.define do
  factory :sale_order_item do
    sale_order { nil }
    product { nil }
    quantity { 1 }
  end
end
