# frozen_string_literal: true

FactoryBot.define do
  factory :supplier_sync_run do
    source { "hlj" }
    mode { "weekly_discovery" }
    status { "queued" }
    processed_count { 0 }
    created_count { 0 }
    updated_count { 0 }
    skipped_count { 0 }
    error_count { 0 }
    metadata { {} }
    error_samples { [] }
  end
end