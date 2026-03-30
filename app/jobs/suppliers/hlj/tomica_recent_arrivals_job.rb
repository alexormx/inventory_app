# frozen_string_literal: true

module Suppliers
  module Hlj
    class TomicaRecentArrivalsJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform
        Suppliers::Hlj::WeeklyDiscoveryJob.perform_now(
          mode: "tomica_recent_arrivals_daily",
          preset: "tomica_recent_arrivals",
          review_feed: "recent_arrivals",
          word: "tomica",
          date_arrivals_within_days: 10,
          fetch_detail: true
        )
      end
    end
  end
end