# frozen_string_literal: true

module Suppliers
  module TomicaFandom
    class WeeklyBackfillJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform
        run = SupplierSyncRun.create!(source: "tomica_fandom", mode: "weekly_backfill", status: "queued")
        run.start!

        processed = 0
        updated = 0
        skipped = 0
        errors = []

        scope.find_each do |catalog_item|
          processed += 1
          result = Suppliers::TomicaFandom::BackfillItemService.new(catalog_item).call
          updated += 1 if result.changed
        rescue StandardError => e
          skipped += 1
          errors << "#{catalog_item.id}: #{e.message}"
        end

        run.complete!(
          processed_count: processed,
          updated_count: updated,
          skipped_count: skipped,
          error_count: errors.size,
          error_samples: errors.first(10),
          metadata: { timezone: "America/Mexico_City" }
        )
      end

      private

      def scope
        SupplierCatalogItem.where.not(canonical_name: [nil, ""]).where("LOWER(COALESCE(canonical_series, '')) LIKE ?", "%tomica%")
      end
    end
  end
end