FactoryBot.define do
  factory :purchase_order do
    association :user, factory: [:user, :supplier]# or just :user if you only have one kind
    order_date { Date.today }
    expected_delivery_date { Date.today + 5.days }
    actual_delivery_date { nil }
    subtotal { 0 }
    shipping_cost { 0 }
    tax_cost { 0 }
    other_cost { 0 }
    currency { "MXN" }
    exchange_rate { 1.0 }
    total_order_cost { 0 }
    total_cost_mxn { 0 }
    total_volume { 0 }
    total_weight { 0 }
    status { "Pending" }
    notes { "" }
  end
end