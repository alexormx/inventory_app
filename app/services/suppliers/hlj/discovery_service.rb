# frozen_string_literal: true

module Suppliers
  module Hlj
    class DiscoveryService
      class StopRequested < StandardError; end

      SEARCH_URL = Suppliers::Hlj::SearchQuery::SEARCH_URL

      def initialize(max_pages: nil, max_items: nil, word: nil, makers: [], genre_code: nil,
                     fetch_detail: true, delay_seconds: 0, connection: nil, run: nil, logger: Rails.logger)
        @max_pages = max_pages
        @max_items = max_items
        @query = Suppliers::Hlj::SearchQuery.new(word: word, makers: makers, genre_code: genre_code)
        @fetch_detail = fetch_detail
        @delay_seconds = delay_seconds.to_f
        @connection = connection
        @run = run || SupplierSyncRun.create!(source: "hlj", mode: "weekly_discovery", status: "queued")
        @logger = logger
      end

      def call
        @run.start! if @run.status == "queued"
        initialize_progress!

        processed = 0
        created = 0
        updated = 0
        skipped = 0
        errors = []

        total_pages.times do |index|
          check_stop_requested!

          page_number = index + 1
          list_doc = fetch_document(page_url(page_number))
          items = Suppliers::Hlj::ExtractListItemsService.new(list_doc).call
          persist_progress(
            processed: processed,
            created: created,
            updated: updated,
            skipped: skipped,
            errors: errors.size,
            page_number: page_number,
            page_item_index: 0,
            page_item_count: items.size
          )

          items.each_with_index do |item, item_index|
            check_stop_requested!

            result = import_item(item)
            processed += 1
            created += 1 if result.created
            updated += 1 unless result.created
            persist_progress(
              processed: processed,
              created: created,
              updated: updated,
              skipped: skipped,
              errors: errors.size,
              page_number: page_number,
              page_item_index: item_index + 1,
              page_item_count: items.size
            )
            sleep(@delay_seconds) if @delay_seconds.positive?
            break if reached_max_items?(processed)
          rescue StandardError => e
            skipped += 1
            errors << "#{item[:external_sku]}: #{e.message}"
            persist_progress(
              processed: processed,
              created: created,
              updated: updated,
              skipped: skipped,
              errors: errors.size,
              page_number: page_number,
              page_item_index: item_index + 1,
              page_item_count: items.size
            )
          end

          break if reached_max_items?(processed)
        end

        @run.complete!(
          processed_count: processed,
          created_count: created,
          updated_count: updated,
          skipped_count: skipped,
          error_count: errors.size,
          error_samples: errors.first(10)
        )
      rescue StopRequested
        @run.cancel!(
          processed_count: processed,
          created_count: created,
          updated_count: updated,
          skipped_count: skipped,
          error_count: errors.size,
          error_samples: errors.first(10),
          metadata: cancellation_metadata
        )
      rescue StandardError => e
        @run.fail!(e.message)
        raise
      end

      private

      def total_pages
        @total_pages ||= begin
          doc = fetch_document(page_url(1))
          last_page = doc.at_css(".pages li:nth-last-child(2)")&.text.to_i
          value = last_page.positive? ? last_page : 1
          @max_pages.present? ? [value, @max_pages].min : value
        end
      end

      def initialize_progress!
        @run.update_progress!(
          counts: {
            processed_count: 0,
            created_count: 0,
            updated_count: 0,
            skipped_count: 0,
            error_count: 0
          },
          metadata: {
            "progress_total_pages" => total_pages,
            "progress_total_items" => @max_items,
            "progress_current_page" => 1,
            "progress_page_item_index" => 0,
            "progress_page_item_count" => 0,
            "progress_started_at" => Time.current.iso8601
          }.compact
        )
      end

      def persist_progress(processed:, created:, updated:, skipped:, errors:, page_number:, page_item_index:, page_item_count:)
        @run.update_progress!(
          counts: {
            processed_count: processed,
            created_count: created,
            updated_count: updated,
            skipped_count: skipped,
            error_count: errors
          },
          metadata: {
            "progress_current_page" => page_number,
            "progress_page_item_index" => page_item_index,
            "progress_page_item_count" => page_item_count,
            "progress_total_pages" => total_pages,
            "progress_total_items" => @max_items
          }.compact
        )
      end

      def page_url(page_number)
        @query.page_url(page_number)
      end

      def import_item(item)
        payload = listing_payload(item)

        if @fetch_detail
          detail_doc = fetch_document(item[:source_url])
          detail_payload = Suppliers::Hlj::ExtractProductDetailsService.new(detail_doc, source_url: item[:source_url]).call
          payload = merge_payloads(payload, detail_payload)
        end

        Suppliers::Catalog::ImportCatalogItemService.new(
          source: "hlj",
          external_sku: item[:external_sku],
          name: payload[:name] || item[:name],
          source_url: payload[:source_url] || item[:source_url],
          raw_status: payload[:raw_status],
          barcode: payload[:barcode],
          supplier_product_code: payload[:supplier_product_code],
          canonical_brand: payload[:canonical_brand],
          canonical_category: payload[:canonical_category],
          canonical_series: payload[:canonical_series],
          canonical_item_type: payload[:canonical_item_type],
          canonical_release_date: payload[:canonical_release_date],
          canonical_price: payload[:canonical_price],
          description_raw: payload[:description_raw],
          image_urls: payload[:image_urls],
          main_image_url: payload[:main_image_url],
          normalized_payload: payload[:normalized_payload],
          raw_payload: payload[:raw_payload]
        ).call
      rescue StandardError => e
        @logger.warn("HLJ detail fallback for #{item[:external_sku]}: #{e.message}")

        Suppliers::Catalog::ImportCatalogItemService.new(
          source: "hlj",
          external_sku: item[:external_sku],
          name: item[:name],
          source_url: item[:source_url],
          raw_status: nil,
          canonical_price: parse_listing_price(item[:listing_price_text]),
          image_urls: Array(item[:listing_image_url]).compact,
          main_image_url: item[:listing_image_url],
          normalized_payload: {},
          raw_payload: { listing_price_text: item[:listing_price_text], detail_error: e.message }
        ).call
      end

      def fetch_document(url)
        Suppliers::Hlj::FetchDocumentService.new(url, connection: @connection).call.document
      end

      def check_stop_requested!
        raise StopRequested if @run.reload.stop_requested?
      end

      def listing_payload(item)
        {
          source_url: item[:source_url],
          name: item[:name],
          raw_status: nil,
          canonical_price: parse_listing_price(item[:listing_price_text]),
          image_urls: Array(item[:listing_image_url]).compact,
          main_image_url: item[:listing_image_url],
          normalized_payload: {},
          raw_payload: { listing_price_text: item[:listing_price_text] }
        }
      end

      def merge_payloads(listing_payload, detail_payload)
        detail_images = Array(detail_payload[:image_urls]).compact_blank
        listing_images = Array(listing_payload[:image_urls]).compact_blank
        combined_images = (detail_images + listing_images).uniq

        listing_payload.merge(detail_payload).merge(
          name: detail_payload[:name].presence || listing_payload[:name],
          canonical_price: detail_payload[:canonical_price].presence || listing_payload[:canonical_price],
          image_urls: combined_images,
          main_image_url: preferred_image(detail_payload[:main_image_url], listing_payload[:main_image_url]),
          raw_payload: listing_payload[:raw_payload].merge(detail_payload[:raw_payload] || {})
        )
      end

      def preferred_image(primary, fallback)
        return fallback if primary.blank? || primary.include?("noImage.png")

        primary
      end

      def parse_listing_price(text)
        return nil if text.blank?

        numeric = text.gsub(/[^\d\.]/, "")
        numeric.present? ? numeric.to_d : nil
      end

      def cancellation_metadata
        current = @run.metadata.is_a?(Hash) ? @run.metadata.deep_dup : {}
        current.merge(
          "cancelled_by_user" => true,
          "cancelled_at" => Time.current.iso8601
        )
      end

      def reached_max_items?(processed)
        @max_items.present? && processed >= @max_items
      end
    end
  end
end