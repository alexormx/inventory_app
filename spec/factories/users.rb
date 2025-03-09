FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    role { "customer" }
    discount_rate { 0.0 } # ensuring not nil

    trait :admin do
      role { "admin" }
    end
  end
end
