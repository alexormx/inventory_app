FactoryBot.define do
  factory :inventory_adjustment do
    status { 'draft' }
    adjustment_type { 'audit' }
    note { 'Test adjustment' }
    user { nil }
  end
end
