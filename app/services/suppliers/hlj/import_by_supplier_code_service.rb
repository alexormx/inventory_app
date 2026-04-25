# frozen_string_literal: true

require "json"

module Suppliers
  module Hlj
    class ImportBySupplierCodeService
      class LookupError < StandardError; end

      LIVE_PRICE_URL = "https://www.hlj.com/search/livePrice/".freeze

      def initialize(supplier_product_code, connection: nil)
        @supplier_product_code = supplier_product_code.to_s.strip
        @connection = connection || Faraday.new
      end

      def call
        raise LookupError, "Supplier ID vacío para consulta HLJ." if @supplier_product_code.blank?

        item = matching_list_item
        return nil unless item

        detail_document = Suppliers::Hlj::FetchDocumentService.new(item[:source_url], connection: @connection).call.document
        payload = Suppliers::Hlj::ExtractProductDetailsService.new(detail_document, source_url: item[:source_url]).call
        return nil unless payload[:supplier_product_code].to_s.casecmp(@supplier_product_code).zero?

        jpy_price, jpy_special_price = fetch_live_price(item[:external_sku])
        effective_price = jpy_price || jpy_special_price || payload[:canonical_price]

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
          canonical_price: effective_price,
          currency: effective_price.present? ? "JPY" : "MXN",
          description_raw: payload[:description_raw],
          image_urls: payload[:image_urls],
          main_image_url: payload[:main_image_url],
          normalized_payload: payload[:normalized_payload],
          raw_payload: payload[:raw_payload].merge(jpy_price: jpy_price, jpy_special_price: jpy_special_price).compact
        ).call.catalog_item
      rescue StandardError => e
        raise LookupError, "No se pudo consultar HLJ para #{@supplier_product_code}: #{e.message}"
      end

      private

      def matching_list_item
        search_url = Suppliers::Hlj::SearchQuery.new(word: @supplier_product_code).page_url(1)
        document = Suppliers::Hlj::FetchDocumentService.new(search_url, connection: @connection).call.document
        items = Suppliers::Hlj::ExtractListItemsService.new(document).call.first(5)

        items.find do |item|
          detail_document = Suppliers::Hlj::FetchDocumentService.new(item[:source_url], connection: @connection).call.document
          payload = Suppliers::Hlj::ExtractProductDetailsService.new(detail_document, source_url: item[:source_url]).call
          payload[:supplier_product_code].to_s.casecmp(@supplier_product_code).zero?
        end
      end

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