FactoryBot.define do
  factory :inventory_adjustment_line do
    association :inventory_adjustment
    association :product
    quantity { 3 }
    direction { 'increase' }
    reason { 'found' }
    unit_cost { 5.0 }
    note { 'Line note' }
  end
end
