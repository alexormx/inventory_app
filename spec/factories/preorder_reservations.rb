# frozen_string_literal: true

FactoryBot.define do
  factory :preorder_reservation do
    association :product
    association :user
    sale_order { nil } # Optional association

    quantity { 1 }
    status { :pending }
    reserved_at { Time.current }

    trait :assigned do
      status { :assigned }
      assigned_at { Time.current }
    end

    trait :completed do
      status { :completed }
      assigned_at { Time.current }
    end

    trait :cancelled do
      status { :cancelled }
    end
  end
end
