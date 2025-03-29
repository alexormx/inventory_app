FactoryBot.define do
  factory :purchase_order_item do
    association :product
    association :purchase_order

    quantity { 1 }
    unit_cost { 100.0 }
    unit_additional_cost { 10.0 }
    unit_compose_cost { unit_cost + unit_additional_cost }
    unit_compose_cost_in_mxn { unit_compose_cost * 1.0 } # default exchange rate
    total_line_cost { quantity * unit_compose_cost }
    total_line_cost_in_mxn { total_line_cost * 1.0 }
    total_line_volume { 100.0 }
    total_line_weight { 10.0 }
  end
end