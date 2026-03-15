# frozen_string_literal: true

module Suppliers
  module Catalog
    class SupplierContextService
      def initialize(product)
        @product = product
      end

      def call
        item = @product.supplier_catalog_item
        return nil unless item

        {
          catalog_item: {
            source_key: item.source_key,
            external_sku: item.external_sku,
            barcode: item.barcode,
            supplier_product_code: item.supplier_product_code,
            canonical_name: item.canonical_name,
            canonical_brand: item.canonical_brand,
            canonical_category: item.canonical_category,
            canonical_series: item.canonical_series,
            canonical_item_type: item.canonical_item_type,
            canonical_release_date: item.canonical_release_date&.iso8601,
            canonical_price: item.canonical_price&.to_f,
            currency: item.currency,
            canonical_status: item.canonical_status,
            source_url: item.source_url,
            main_image_url: item.main_image_url,
            image_urls: Array(item.image_urls),
            description_raw: item.description_raw,
            last_seen_at: item.last_seen_at&.iso8601,
            last_status_change_at: item.last_status_change_at&.iso8601,
            details_payload: item.details_payload
          },
          sources: item.supplier_catalog_sources.order(:source).map do |source|
            {
              source: source.source,
              external_id: source.external_id,
              source_url: source.source_url,
              fetch_status: source.fetch_status,
              image_urls: Array(source.image_urls),
              normalized_payload: source.normalized_payload,
              metadata: source.metadata,
              last_seen_at: source.last_seen_at&.iso8601,
              last_changed_at: source.last_changed_at&.iso8601
            }
          end
        }
      end
    end
  end
end