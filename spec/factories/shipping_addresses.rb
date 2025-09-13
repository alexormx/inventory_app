FactoryBot.define do
  factory :shipping_address do
    association :user
    label { 'Casa' }
    full_name { 'John Tester' }
    line1 { 'Calle Falsa 123' }
    line2 { nil }
    city { 'Ciudad' }
    state { 'Estado' }
    postal_code { '12345' }
    country { 'MX' }
    default { true }
  end
end
