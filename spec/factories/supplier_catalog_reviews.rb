# frozen_string_literal: true

FactoryBot.define do
  factory :supplier_catalog_review do
    association :supplier_catalog_item
    association :reviewed_by, factory: :user
    review_mode { "recent_additions" }
    reviewed_at { Time.current }
    notes { nil }
  end
end