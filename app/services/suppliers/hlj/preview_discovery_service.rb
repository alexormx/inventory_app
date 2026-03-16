# frozen_string_literal: true

require "json"

module Suppliers
  module Hlj
    class PreviewDiscoveryService
      SAMPLE_LIMIT = 16
      MAX_PREVIEW_PAGES = 3
      LIVE_PRICE_URL = "https://www.hlj.com/search/livePrice/".freeze
      Result = Struct.new(:total_found, :sample_items, :scanned_pages, :available_pages, :sample_limit, keyword_init: true)

      def initialize(max_pages: nil, word: nil, makers: [], genre_codes: [], scales: [], series: nil, connection: nil)
        @max_pages = max_pages || MAX_PREVIEW_PAGES
        @query = SearchQuery.new(word: word, makers: makers, genre_codes: genre_codes, scales: scales, series: series)
        @connection = connection || Faraday.new
      end

      def call
        items = []

        # Page 1 is already fetched by total_pages; reuse it
        items.concat(Suppliers::Hlj::ExtractListItemsService.new(first_page_document).call)

        # Fetch remaining pages (2..pages_to_scan)
        (2..pages_to_scan).each do |page|
          document = fetch_document(@query.page_url(page))
          items.concat(Suppliers::Hlj::ExtractListItemsService.new(document).call)
        end

        sample = items.first(SAMPLE_LIMIT)
        enrich_with_live_prices!(sample)

        Result.new(
          total_found: items.size,
          sample_items: sample,
          scanned_pages: pages_to_scan,
          available_pages: total_pages,
          sample_limit: SAMPLE_LIMIT
        )
      end

      private

      def first_page_document
        @first_page_document ||= fetch_document(@query.page_url(1))
      end

      def total_pages
        @total_pages ||= begin
          last_page = first_page_document.at_css(".pages li:nth-last-child(2)")&.text.to_i
          last_page.positive? ? last_page : 1
        end
      end

      def pages_to_scan
        @pages_to_scan ||= @max_pages.present? ? [total_pages, @max_pages].min : total_pages
      end

      def fetch_document(url)
        Suppliers::Hlj::FetchDocumentService.new(url, connection: @connection).call.document
      end

      def enrich_with_live_prices!(items)
        skus = items.map { |i| i[:external_sku] }.compact
        return if skus.empty?

        response = @connection.get(LIVE_PRICE_URL) do |req|
          req.headers["User-Agent"] = Suppliers::Hlj::FetchDocumentService::BASE_HEADERS["User-Agent"]
          req.params["item_codes"] = skus.join(",")
          req.options.timeout = 10
        end

        return unless response.success?

        price_data = JSON.parse(response.body)
        items.each do |item|
          info = price_data[item[:external_sku]]
          next unless info

          item[:jpy_price] = info["JPYprice"]
          item[:jpy_special_price] = info["JPYspecial_price"]
          item[:availability] = info["availability"]
          item[:stock_status] = info["stockStatusCode"]
        end
      rescue StandardError
        # Non-critical: preview works without prices
      end
    end
  end
end