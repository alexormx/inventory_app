# frozen_string_literal: true

module Suppliers
  module Hlj
    class DiscoveryService
      SEARCH_URL = "https://www.hlj.com/search/?".freeze

      def initialize(max_pages: nil, fetch_detail: true, delay_seconds: 0, connection: nil, run: nil, logger: Rails.logger)
        @max_pages = max_pages
        @fetch_detail = fetch_detail
        @delay_seconds = delay_seconds.to_f
        @connection = connection
        @run = run || SupplierSyncRun.create!(source: "hlj", mode: "weekly_discovery", status: "queued")
        @logger = logger
      end

      def call
        @run.start! if @run.status == "queued"

        processed = 0
        created = 0
        updated = 0
        skipped = 0
        errors = []

        total_pages.times do |index|
          page_number = index + 1
          list_doc = fetch_document(page_url(page_number))
          items = Suppliers::Hlj::ExtractListItemsService.new(list_doc).call

          items.each do |item|
            result = import_item(item)
            processed += 1
            created += 1 if result.created
            updated += 1 unless result.created
            sleep(@delay_seconds) if @delay_seconds.positive?
          rescue StandardError => e
            skipped += 1
            errors << "#{item[:external_sku]}: #{e.message}"
          end
        end

        @run.complete!(
          processed_count: processed,
          created_count: created,
          updated_count: updated,
          skipped_count: skipped,
          error_count: errors.size,
          error_samples: errors.first(10)
        )
      rescue StandardError => e
        @run.fail!(e.message)
        raise
      end

      private

      def total_pages
        @total_pages ||= begin
          doc = fetch_document(SEARCH_URL)
          last_page = doc.at_css(".pages li:nth-last-child(2)")&.text.to_i
          value = last_page.positive? ? last_page : 1
          @max_pages.present? ? [value, @max_pages].min : value
        end
      end

      def page_url(page_number)
        return SEARCH_URL if page_number == 1

        "#{SEARCH_URL}&Page=#{page_number}"
      end

      def import_item(item)
        payload = if @fetch_detail
                    detail_doc = fetch_document(item[:source_url])
                    Suppliers::Hlj::ExtractProductDetailsService.new(detail_doc, source_url: item[:source_url]).call
                  else
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
      end

      def fetch_document(url)
        Suppliers::Hlj::FetchDocumentService.new(url, connection: @connection).call.document
      end

      def parse_listing_price(text)
        return nil if text.blank?

        numeric = text.gsub(/[^\d\.]/, "")
        numeric.present? ? numeric.to_d : nil
      end
    end
  end
end