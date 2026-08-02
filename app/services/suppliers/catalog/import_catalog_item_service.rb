# frozen_string_literal: true

require "digest"

module Suppliers
  module Catalog
    class ImportCatalogItemService
      Result = Struct.new(:catalog_item, :catalog_source, :created, :changed, :status_changed, :price_changed,
                          keyword_init: true)

      # Marcas de tiempo y banderas de control: cambian en cada pasada, así que
      # no sirven para decidir si el contenido del producto realmente cambió.
      BOOKKEEPING_ATTRIBUTES = %w[
        last_seen_at source_last_synced_at last_full_sync_at last_status_change_at
        last_hlj_recent_added_at last_hlj_recent_arrival_at needs_review
        created_at updated_at
      ].freeze

      def initialize(source:, external_sku:, name:, source_url:, raw_status:, normalized_payload: {}, raw_payload: {},
                     barcode: nil, supplier_product_code: nil, canonical_brand: nil, canonical_category: nil,
                     canonical_series: nil, canonical_item_type: nil, canonical_release_date: nil,
                     canonical_price: nil, currency: "MXN", description_raw: nil, image_urls: [],
                     main_image_url: nil, sync_linked_product: false, review_feed: nil, full_sync: true)
        @source = source.to_s
        @external_sku = external_sku.to_s.strip
        @name = name.to_s.strip
        @source_url = source_url.to_s.strip
        @raw_status = raw_status.to_s.strip
        @normalized_payload = normalized_payload || {}
        @raw_payload = raw_payload || {}
        @barcode = barcode.presence
        @supplier_product_code = supplier_product_code.presence
        @canonical_brand = canonical_brand.presence
        @canonical_category = canonical_category.presence
        @canonical_series = canonical_series.presence
        @canonical_item_type = canonical_item_type.presence
        @canonical_release_date = canonical_release_date
        @canonical_price = canonical_price
        @currency = currency.presence || "MXN"
        @description_raw = description_raw.presence
        @image_urls = Array(image_urls).compact_blank
        @main_image_url = main_image_url.presence || @image_urls.first
        @sync_linked_product = sync_linked_product
        @review_feed = review_feed.presence
        @full_sync = full_sync
      end

      def call
        raise ArgumentError, "external_sku is required" if @external_sku.blank?
        raise ArgumentError, "name is required" if @name.blank?

        normalized_status = Suppliers::Hlj::NormalizeStatusService.new(@raw_status).call if @source == "hlj"
        normalized_status ||= @raw_status.presence

        catalog_item = nil
        catalog_source = nil
        created = false
        changed = false
        status_changed = false
        price_changed = false

        ActiveRecord::Base.transaction do
          catalog_item = find_or_initialize_catalog_item
          created = catalog_item.new_record?
          previous_status = catalog_item.canonical_status
          checksum = Digest::SHA256.hexdigest(@normalized_payload.to_json)
          now = Time.current

          catalog_item.assign_attributes(
            source_key: @source,
            external_sku: @external_sku,
            canonical_name: @name,
            source_url: @source_url,
            content_checksum: checksum
          )
          assign_preserving_existing!(
            catalog_item,
            barcode: @barcode,
            supplier_product_code: @supplier_product_code,
            canonical_brand: @canonical_brand,
            canonical_category: @canonical_category,
            canonical_series: @canonical_series,
            canonical_item_type: @canonical_item_type,
            canonical_release_date: @canonical_release_date,
            canonical_price: @canonical_price,
            currency: @currency,
            canonical_status: normalized_status,
            main_image_url: @main_image_url,
            image_urls: @image_urls,
            description_raw: @description_raw,
            details_payload: @normalized_payload,
            raw_payload: @raw_payload
          )

          # Se mide antes de tocar las marcas de tiempo: éstas cambian en cada
          # pasada y harían que todo producto pareciera modificado.
          changed = created || (catalog_item.changed - BOOKKEEPING_ATTRIBUTES).any?
          price_changed = catalog_item.canonical_price_changed? || catalog_item.currency_changed?
          status_changed = previous_status.present? && previous_status != catalog_item.canonical_status

          catalog_item.last_seen_at = now
          catalog_item.source_last_synced_at = now
          catalog_item.last_full_sync_at = now if @full_sync
          catalog_item.last_status_change_at = now if created || status_changed
          apply_review_tracking!(catalog_item, now, changed: changed || status_changed, created: created)

          catalog_item.save! if catalog_item.changed?

          auto_link_product!(catalog_item) if catalog_item.product_id.blank?

          catalog_source = catalog_item.supplier_catalog_sources.find_or_initialize_by(source: @source)
          previous_source_checksum = catalog_source.content_checksum
          catalog_source.assign_attributes(
            external_id: @external_sku,
            source_url: @source_url,
            fetch_status: "ok",
            last_error_message: nil,
            image_urls: @image_urls,
            normalized_payload: @normalized_payload,
            raw_payload: @raw_payload,
            metadata: {
              barcode: @barcode,
              supplier_product_code: @supplier_product_code,
              canonical_status: normalized_status
            },
            content_checksum: checksum,
            last_seen_at: now,
            last_changed_at: previous_source_checksum == checksum ? catalog_source.last_changed_at : now
          )
          catalog_source.save!

          if @sync_linked_product && catalog_item.product.present?
            Suppliers::Catalog::SyncProductService.new(catalog_item, product: catalog_item.product).call
          end
        end

        Result.new(catalog_item: catalog_item, catalog_source: catalog_source, created: created,
                   changed: changed, status_changed: status_changed, price_changed: price_changed)
      end

      private

      # Un campo ausente en la respuesta de HLJ significa "no vino en esta
      # pasada", no "el proveedor lo borró". Sobrescribir con nil perdería
      # imágenes y descripciones ya capturadas por una sincronización previa.
      def assign_preserving_existing!(catalog_item, attributes)
        attributes.each do |name, value|
          next if value.blank? && catalog_item.public_send(name).present?

          catalog_item.public_send(:"#{name}=", value)
        end
      end

      def find_or_initialize_catalog_item
        SupplierCatalogItem.find_by(source_key: @source, external_sku: @external_sku) ||
          find_by_linkable_identifiers ||
          SupplierCatalogItem.new
      end

      def find_by_linkable_identifiers
        return SupplierCatalogItem.find_by(barcode: @barcode) if @barcode.present?
        return SupplierCatalogItem.find_by(supplier_product_code: @supplier_product_code) if @supplier_product_code.present?

        nil
      end

      def auto_link_product!(catalog_item)
        product = Product.find_by(supplier_product_code: catalog_item.external_sku)
        product ||= Product.find_by(barcode: catalog_item.barcode) if catalog_item.barcode.present?

        return unless product
        return if product.supplier_catalog_item.present?

        catalog_item.update!(product_id: product.id)
      end

      # La marca de tiempo del feed se refresca siempre, pero needs_review solo
      # se enciende ante un alta o un cambio real: marcarlo en cada pasada
      # llenaba la bandeja de revisión con miles de productos idénticos.
      def apply_review_tracking!(catalog_item, now, changed:, created:)
        case @review_feed
        when "recent_additions" then catalog_item.last_hlj_recent_added_at = now
        when "recent_arrivals" then catalog_item.last_hlj_recent_arrival_at = now
        else return
        end

        catalog_item.needs_review = true if created || changed
      end
    end
  end
end