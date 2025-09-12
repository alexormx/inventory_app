FactoryBot.define do
  factory :inventory_adjustment_entry do
    association :inventory_adjustment_line
    association :inventory
    action { 'created' }
  end
end
