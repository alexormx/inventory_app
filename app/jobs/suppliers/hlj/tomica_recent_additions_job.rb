# frozen_string_literal: true

module Suppliers
  module Hlj
    class TomicaRecentAdditionsJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform
        Suppliers::Hlj::WeeklyDiscoveryJob.perform_now(
          mode: "tomica_recent_additions_daily",
          preset: "tomica_recent_additions",
          review_feed: "recent_additions",
          word: "tomica",
          date_added_within_days: 10,
          fetch_detail: true
        )
      end
    end
  end
end