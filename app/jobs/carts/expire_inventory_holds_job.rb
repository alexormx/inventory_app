# frozen_string_literal: true

module Carts
  # Deletes cart holds whose deadline has passed.
  #
  # This is hygiene, never correctness. An expired hold is already logically
  # inactive the instant `expires_at` passes: every reader filters on
  # CartInventoryHold.active (database time), and the atomic claim reclaims an
  # expired row in place. If this job never ran, availability, allocation and
  # checkout would all still behave correctly - the table would simply keep
  # dead rows around.
  class ExpireInventoryHoldsJob < ApplicationJob
    queue_as :default

    def perform
      count = CartInventoryHold.expired.delete_all
      Rails.logger.info("[Carts::ExpireInventoryHoldsJob] Removed #{count} expired cart inventory holds")
      count
    end
  end
end
