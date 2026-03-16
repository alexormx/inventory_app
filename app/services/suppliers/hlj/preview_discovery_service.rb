# frozen_string_literal: true

module Suppliers
  module Hlj
    class PreviewDiscoveryService
      SAMPLE_LIMIT = 16
      MAX_PREVIEW_PAGES = 3
      Result = Struct.new(:total_found, :sample_items, :scanned_pages, :available_pages, :sample_limit, keyword_init: true)

      def initialize(max_pages: nil, word: nil, makers: [], genre_code: nil, connection: nil)
        @max_pages = max_pages || MAX_PREVIEW_PAGES
        @query = SearchQuery.new(word: word, makers: makers, genre_code: genre_code)
        @connection = connection
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

        Result.new(
          total_found: items.size,
          sample_items: items.first(SAMPLE_LIMIT),
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
    end
  end
end