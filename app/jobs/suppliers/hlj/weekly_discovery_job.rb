# frozen_string_literal: true

module Suppliers
  module Hlj
    class WeeklyDiscoveryJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

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
          fetch_detail: normalized.key?(:fetch_detail) ? normalized[:fetch_detail] : true,
          run: run
        ).call
      end

      private

      def build_metadata(options)
        {
          "preset" => options[:preset],
          "word" => options[:word],
          "makers" => Array(options[:makers]).compact_blank,
          "genre_code" => options[:genre_code],
          "max_pages" => options[:max_pages],
          "max_items" => options[:max_items],
          "fetch_detail" => options.key?(:fetch_detail) ? options[:fetch_detail] : true
        }.compact
      end
    end
  end
end