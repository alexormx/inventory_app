# frozen_string_literal: true

module Suppliers
  module Catalog
    # Actualización ligera de un ítem de catálogo ya existente: solo estado,
    # precio y marcas de tiempo.
    #
    # Se usa en lugar de ImportCatalogItemService cuando no se descargó la
    # página de detalle. El importador completo reescribe nombre, descripción,
    # imágenes y payloads con lo que traiga el listado, así que aplicarlo sin
    # detalle degradaría datos que ya estaban bien.
    class UpdateListingStateService
      Result = Struct.new(:catalog_item, :changed, :status_changed, :price_changed, keyword_init: true)

      # `touch_timestamps: false` permite que un job masivo agrupe el refresco
      # de last_seen_at/source_last_synced_at en un solo update_all por lote en
      # vez de una escritura por producto.
      def initialize(catalog_item:, status: nil, price: nil, currency: nil,
                     review_feed: nil, touch_timestamps: true, now: nil)
        @catalog_item = catalog_item
        @status = status.presence
        @price = price
        @currency = currency.presence
        @review_feed = review_feed.presence
        @touch_timestamps = touch_timestamps
        @now = now || Time.current
      end

      def call
        status_changed = apply_status!
        price_changed = apply_price!
        changed = status_changed || price_changed

        # Solo se marca para revisión ante un cambio real; marcarlo en cada
        # pasada generaba miles de revisiones falsas para productos idénticos.
        @catalog_item.needs_review = true if changed && @review_feed.present?
        apply_review_timestamp! if @review_feed.present?

        if @touch_timestamps
          @catalog_item.last_seen_at = @now
          @catalog_item.source_last_synced_at = @now
        end

        @catalog_item.save! if @catalog_item.changed?

        Result.new(
          catalog_item: @catalog_item,
          changed: changed,
          status_changed: status_changed,
          price_changed: price_changed
        )
      end

      private

      # Un estado vacío o desconocido deja el valor actual intacto: que HLJ no
      # responda no significa que el producto perdió su estado.
      def apply_status!
        return false if @status.blank?
        return false if @status == @catalog_item.canonical_status

        @catalog_item.canonical_status = @status
        @catalog_item.last_status_change_at = @now
        true
      end

      # Precio y moneda se mueven juntos: escribir un precio en JPY dejando la
      # moneda anterior produciría un valor sin sentido.
      def apply_price!
        return false if @price.blank?

        new_price = normalize_price(@price)
        return false if new_price.nil?

        new_currency = @currency || @catalog_item.currency
        return false if new_price == @catalog_item.canonical_price && new_currency == @catalog_item.currency

        @catalog_item.canonical_price = new_price
        @catalog_item.currency = new_currency
        true
      end

      def normalize_price(value)
        decimal = BigDecimal(value.to_s)
        decimal.negative? ? nil : decimal
      rescue ArgumentError, TypeError
        nil
      end

      def apply_review_timestamp!
        case @review_feed
        when "recent_additions" then @catalog_item.last_hlj_recent_added_at = @now
        when "recent_arrivals" then @catalog_item.last_hlj_recent_arrival_at = @now
        end
      end
    end
  end
end
