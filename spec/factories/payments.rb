FactoryBot.define do
  factory :payment do
    association :sale_order
    amount { 10.0 }
    payment_method { "efectivo" }
    status { "Completed" }
  end
end