# frozen_string_literal: true

module Suppliers
  module TomicaFandom
    class WeeklyBackfillJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform
        run = SupplierSyncRun.create!(source: "tomica_fandom", mode: "weekly_backfill", status: "queued")
        run.start!
        run.complete!(metadata: {
          note: "Foundation job created for tertiary historical backfill by model name.",
          timezone: "America/Mexico_City"
        })
      end
    end
  end
end