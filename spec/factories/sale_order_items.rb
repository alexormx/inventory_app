FactoryBot.define do
  factory :sale_order_item do
    association :sale_order
    association :product
    quantity { 1 }
    unit_cost { 10.0 }
    unit_discount { 0.0 }
    unit_final_price { unit_cost }
    total_line_cost { quantity * unit_final_price }
    total_line_volume { 1.0 }
    total_line_weight { 1.0 }
  end
end
