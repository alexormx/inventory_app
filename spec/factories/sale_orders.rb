FactoryBot.define do
  factory :sale_order do
    association :user
    order_date { Date.today }
    subtotal { 100.0 }
    tax_rate { 0.0 }
    total_tax { 0.0 }
    total_order_value { 100.0 }
    status { "Pending" }
  end
end
