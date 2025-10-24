# frozen_string_literal: true

FactoryBot.define do
  factory :order_shipping_address do
    association :sale_order
    full_name { "John Doe" }
    line1 { "123 Main St" }
    line2 { "Apt 4B" }
    city { "Test City" }
    state { "Test State" }
    postal_code { "12345" }
    country { "Mexico" }
    shipping_method { "standard" }
  end
end
