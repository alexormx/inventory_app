# frozen_string_literal: true

require "digest"

module Suppliers
  module TakaraTomyMall
    class BackfillItemService
      Result = Struct.new(:catalog_item, :catalog_source, :changed, keyword_init: true)

      def initialize(catalog_item, connection: nil)
        @catalog_item = catalog_item
        @connection = connection
      end

      def call
        raise ArgumentError, "Catalog item must have a barcode" if @catalog_item.barcode.blank?

        source_url = Suppliers::TakaraTomyMall::BuildUrlService.new(@catalog_item.barcode).call
        fetch_result = Suppliers::TakaraTomyMall::FetchDocumentService.new(source_url, connection: @connection).call
        payload = Suppliers::TakaraTomyMall::ExtractProductDetailsService.new(fetch_result.document, source_url: fetch_result.url, barcode: @catalog_item.barcode).call
        checksum = Digest::SHA256.hexdigest(payload[:normalized_payload].to_json)
        changed = false

        ActiveRecord::Base.transaction do
          source = @catalog_item.supplier_catalog_sources.find_or_initialize_by(source: "takaratomy_mall")
          previous_checksum = source.content_checksum
          now = Time.current

          source.assign_attributes(
            external_id: @catalog_item.barcode,
            source_url: payload[:source_url],
            fetch_status: "ok",
            last_http_status: fetch_result.status,
            last_error_message: nil,
            image_urls: payload[:image_urls],
            normalized_payload: payload[:normalized_payload],
            raw_payload: payload[:raw_payload],
            metadata: {
              barcode: @catalog_item.barcode,
              image_count: payload[:image_urls].size,
              description_present: payload[:description].present?
            },
            content_checksum: checksum,
            last_seen_at: now,
            last_changed_at: previous_checksum == checksum ? source.last_changed_at : now
          )
          source.save!

          changed = previous_checksum != checksum
          enrich_catalog_item!(payload) if changed

          Result.new(catalog_item: @catalog_item, catalog_source: source, changed: changed)
        end
      rescue StandardError => e
        upsert_failed_source(e)
        raise
      end

      private

      def enrich_catalog_item!(payload)
        merged_images = (Array(@catalog_item.image_urls) + Array(payload[:image_urls])).uniq
        merged_details = @catalog_item.details_payload.merge(
          "takara_tomy_mall" => payload[:normalized_payload]
        )

        @catalog_item.update!(
          image_urls: merged_images,
          main_image_url: @catalog_item.main_image_url.presence || payload[:main_image_url],
          description_raw: @catalog_item.description_raw.presence || payload[:description],
          details_payload: merged_details,
          raw_payload: @catalog_item.raw_payload.merge("takara_tomy_mall" => payload[:raw_payload]),
          source_last_synced_at: Time.current,
          needs_review: true
        )
      end

      def upsert_failed_source(error)
        source = @catalog_item.supplier_catalog_sources.find_or_initialize_by(source: "takaratomy_mall")
        source.assign_attributes(
          external_id: @catalog_item.barcode,
          source_url: Suppliers::TakaraTomyMall::BuildUrlService.new(@catalog_item.barcode).call,
          fetch_status: "failed",
          last_error_message: error.message,
          last_seen_at: Time.current
        )
        source.save!
      rescue StandardError
        nil
      end
    end
  end
end