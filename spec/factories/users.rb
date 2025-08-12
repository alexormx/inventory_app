FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    role { "customer" }
    discount_rate { 0.0 } # ensuring not nil
    
    # If your model includes :confirmable:
    confirmed_at { Time.current }
    after(:build) { |u| u.skip_confirmation_notification! }

    trait :admin do
      role { "admin" }
    end

    trait :supplier do
      role { "supplier" }
    end
  end
end
