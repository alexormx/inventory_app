# frozen_string_literal: true

FactoryBot.define do
  factory :shopping_cart do
    status { 'active' }
    last_activity_at { Time.current }

    trait :anonymous do
      user { nil }
      anonymous_token_digest { SecureRandom.hex(32) }
    end

    trait :owned do
      association :user
    end

    trait :converted do
      status { 'converted' }
      # SaleOrder's primary key is a string generated at creation time, so the
      # associated record must actually be persisted (not merely built) for
      # sale_order_id to be populated - force :create regardless of the
      # parent's own build strategy.
      association :sale_order, strategy: :create
      converted_at { Time.current }
      closed_at { Time.current }
    end

    trait :merged do
      status { 'merged' }
      closed_at { Time.current }
      after(:build) do |cart|
        cart.merged_into_cart ||= create(:shopping_cart, :owned)
      end
    end

    trait :cleared do
      status { 'cleared' }
      closed_at { Time.current }
    end
  end
end
