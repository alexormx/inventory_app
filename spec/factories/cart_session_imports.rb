# frozen_string_literal: true

FactoryBot.define do
  factory :cart_session_import do
    association :shopping_cart
    sequence(:import_key_digest) { |n| "import-key-#{n}-#{SecureRandom.hex(8)}" }
    source_payload_digest { SecureRandom.hex(32) }
    source_payload { { '1' => { 'brand_new' => 2 } } }
  end
end
