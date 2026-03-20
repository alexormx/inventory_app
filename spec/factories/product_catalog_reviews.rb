# frozen_string_literal: true

FactoryBot.define do
  factory :product_catalog_review do
    product
    reviewed_at { Time.current }
    review_mode { "unlinked" }
  end
end
