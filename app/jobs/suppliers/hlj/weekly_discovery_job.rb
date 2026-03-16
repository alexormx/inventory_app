# frozen_string_literal: true

module Suppliers
  module Hlj
    class WeeklyDiscoveryJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      discard_on(StandardError) do |job, error|
        run_id = job.arguments.first&.dig(:run_id) || job.arguments.first&.dig("run_id")
        if run_id && (run = SupplierSyncRun.find_by(id: run_id))
          run.fail!("Job descartado tras reintentos: #{error.message}")
        end
      end

      def perform(options = {})
        normalized = options.to_h.deep_symbolize_keys
        run = SupplierSyncRun.create!(
          source: "hlj",
          mode: normalized[:mode].presence || "weekly_discovery",
          status: "queued",
          metadata: build_metadata(normalized)
        )

        Suppliers::Hlj::DiscoveryService.new(
          max_pages: normalized[:max_pages],
          max_items: normalized[:max_items],
          word: normalized[:word],
          makers: normalized[:makers],
          genre_code: normalized[:genre_code],
          scale: normalized[:scale],
          series: normalized[:series],
          fetch_detail: normalized.key?(:fetch_detail) ? normalized[:fetch_detail] : true,
          run: run
        ).call
      rescue StandardError => e
        run&.fail!(e.message) if run&.persisted? && !run&.reload&.status&.in?(%w[completed failed cancelled])
        raise
      end

      private

      def build_metadata(options)
        {
          "preset" => options[:preset],
          "word" => options[:word],
          "makers" => Array(options[:makers]).compact_blank,
          "genre_code" => options[:genre_code],
          "scale" => options[:scale],
          "series" => options[:series],
          "max_pages" => options[:max_pages],
          "max_items" => options[:max_items],
          "fetch_detail" => options.key?(:fetch_detail) ? options[:fetch_detail] : true
        }.compact
      end
    end
  end
end