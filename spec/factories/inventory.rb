FactoryBot.define do
  factory :inventory do
    association :product
    purchase_cost { 10.0 }
    status { :available }
    source { 'seed' }
    notes { 'Factory inventory item' }
  end
end
