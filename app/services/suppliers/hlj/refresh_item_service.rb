# frozen_string_literal: true

require "json"

module Suppliers
  module Hlj
    class RefreshItemService
      LIVE_PRICE_URL = "https://www.hlj.com/search/livePrice/".freeze

      def initialize(catalog_item, connection: nil)
        @catalog_item = catalog_item
        @connection = connection || Faraday.new
      end

      def call
        raise ArgumentError, "Catalog item must have an HLJ source URL" if @catalog_item.source_url.blank?

        document = Suppliers::Hlj::FetchDocumentService.new(@catalog_item.source_url, connection: @connection).call.document
        payload = Suppliers::Hlj::ExtractProductDetailsService.new(document, source_url: @catalog_item.source_url).call

        jpy_price, jpy_special_price = fetch_live_price(@catalog_item.external_sku)
        effective_price = jpy_price || jpy_special_price

        Suppliers::Catalog::ImportCatalogItemService.new(
          source: @catalog_item.source_key,
          external_sku: @catalog_item.external_sku,
          name: payload[:name] || @catalog_item.canonical_name,
          source_url: payload[:source_url] || @catalog_item.source_url,
          raw_status: payload[:raw_status],
          barcode: payload[:barcode] || @catalog_item.barcode,
          supplier_product_code: payload[:supplier_product_code] || @catalog_item.supplier_product_code,
          canonical_brand: payload[:canonical_brand] || @catalog_item.canonical_brand,
          canonical_category: payload[:canonical_category] || @catalog_item.canonical_category,
          canonical_series: payload[:canonical_series] || @catalog_item.canonical_series,
          canonical_item_type: payload[:canonical_item_type] || @catalog_item.canonical_item_type,
          canonical_release_date: payload[:canonical_release_date] || @catalog_item.canonical_release_date,
          canonical_price: effective_price || payload[:canonical_price] || @catalog_item.canonical_price,
          currency: effective_price ? "JPY" : (@catalog_item.currency || "JPY"),
          description_raw: payload[:description_raw] || @catalog_item.description_raw,
          image_urls: payload[:image_urls],
          main_image_url: payload[:main_image_url],
          normalized_payload: payload[:normalized_payload],
          raw_payload: payload[:raw_payload].merge(jpy_price: jpy_price, jpy_special_price: jpy_special_price).compact
        ).call
      end

      private

      def fetch_live_price(sku)
        response = @connection.get(LIVE_PRICE_URL) do |req|
          req.headers["User-Agent"] = Suppliers::Hlj::FetchDocumentService::BASE_HEADERS["User-Agent"]
          req.params["item_codes"] = sku
          req.options.timeout = 10
        end

        return [nil, nil] unless response.success?

        data = JSON.parse(response.body)
        info = data[sku]
        return [nil, nil] unless info

        [info["JPYprice"], info["JPYspecial_price"]]
      rescue StandardError
        [nil, nil]
      end
    end
  end
end