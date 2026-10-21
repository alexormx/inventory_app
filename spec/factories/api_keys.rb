# frozen_string_literal: true

FactoryBot.define do
  factory :api_key do
    sequence(:name) { |n| "Integración #{n}" }
    token_digest { ApiKey.digest("pk_#{SecureRandom.base58(40)}") }
    token_prefix { 'pk_test0000' }
    scopes { ApiKey::SCOPES }
    association :created_by, factory: %i[user admin]
  end
end
