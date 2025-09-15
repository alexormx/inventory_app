FactoryBot.define do
  factory :user do
  # Add random hex to guarantee uniqueness even if FactoryBot sequences reset between reloads
  sequence(:email) { |n| "user#{n}-#{SecureRandom.hex(3)}@example.com" }
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
