FactoryBot.define do
  factory :user do
    email { Faker::Internet.unique.email }
    password { "password123" }
    password_confirmation { "password123" }
    role { "customer" }
    discount_rate { 0.0 } # ensuring not nil
  end
end
