# frozen_string_literal: true

module Suppliers
  module Hlj
    # Sincronización ligera de estado y precio para el catálogo HLJ ya conocido.
    #
    # No descarga ni una sola página de producto: pregunta por lotes al endpoint
    # livePrice y escribe solo cuando algo cambió de verdad. Es la contraparte
    # barata de DiscoveryService, que existe para descubrir SKUs nuevos.
    class StatusSyncService
      # Columnas mínimas para decidir y guardar. Traer details_payload/raw_payload
      # multiplicaría por varios órdenes la memoria de cada lote.
      SELECTED_COLUMNS = %i[
        id source_key external_sku canonical_name canonical_status canonical_price currency
        last_status_change_at needs_review last_seen_at source_last_synced_at
        last_hlj_recent_added_at last_hlj_recent_arrival_at
      ].freeze

      DEFAULT_BATCH_SIZE = 250

      def initialize(run: nil, scope: nil, batch_size: nil, max_items: nil, connection: nil,
                     live_price_service: nil, logger: Rails.logger)
        @run = run || SupplierSyncRun.create!(source: "hlj", mode: "hlj_status_sync", status: "queued")
        @scope = scope || SupplierCatalogItem.where(source_key: "hlj")
        @batch_size = (batch_size || DEFAULT_BATCH_SIZE).to_i
        @max_items = max_items
        @live_price_service = live_price_service ||
                              Suppliers::Hlj::LivePriceService.new(connection: connection || Faraday.new, logger: logger)
        @logger = logger
        @errors = []
        @counts = Hash.new(0)
      end

      def call
        @run.start! if @run.status == "queued"
        now = Time.current

        @scope.select(*SELECTED_COLUMNS).find_in_batches(batch_size: @batch_size) do |batch|
          break if @run.reload.stop_requested?

          process_batch(batch, now)
          persist_progress
          break if reached_max_items?
        end

        @run.complete!(**run_counts, metadata: completion_metadata)
        @counts
      rescue StandardError => e
        @run.fail!(e.message)
        raise
      end

      private

      def process_batch(batch, now)
        result = @live_price_service.call(batch.map(&:external_sku))
        touched_ids = []

        batch.each do |catalog_item|
          @counts[:processed] += 1

          # Un SKU que el endpoint no devolvió no se toca: puede ser un lote
          # caído, y escribir nil borraría estado y precio válidos.
          unless result.fetched?(catalog_item.external_sku)
            @counts[:skipped] += 1
            next
          end

          apply_entry(catalog_item, result[catalog_item.external_sku], now)
          touched_ids << catalog_item.id
          break if reached_max_items?
        rescue StandardError => e
          @counts[:errors] += 1
          @errors << "#{catalog_item.external_sku}: #{e.message}"
        end

        touch_seen!(touched_ids, now)
        @counts[:failed_lookups] += result.failed_skus.size
      end

      def apply_entry(catalog_item, info, now)
        info = {} unless info.is_a?(Hash)
        price = info["JPYprice"].presence || info["JPYspecial_price"].presence

        update = Suppliers::Catalog::UpdateListingStateService.new(
          catalog_item: catalog_item,
          status: Suppliers::Hlj::NormalizeStatusService.from_live_price(
            availability: info["availability"],
            stock_status_code: info["stockStatusCode"],
            logger: @logger
          ),
          price: price,
          currency: price.present? ? "JPY" : nil,
          touch_timestamps: false,
          now: now
        ).call

        if update.changed
          @counts[:updated] += 1
        else
          @counts[:unchanged] += 1
        end
        @counts[:status_changed] += 1 if update.status_changed
        @counts[:price_changed] += 1 if update.price_changed
      end

      # Un UPDATE por lote en vez de uno por producto sin cambios.
      def touch_seen!(ids, now)
        return if ids.empty?

        SupplierCatalogItem.where(id: ids).update_all(last_seen_at: now, source_last_synced_at: now)
      end

      def reached_max_items?
        @max_items.present? && @counts[:processed] >= @max_items
      end

      def persist_progress
        @run.update_progress!(counts: run_counts.slice(:processed_count, :updated_count, :skipped_count, :error_count))
      end

      def run_counts
        {
          processed_count: @counts[:processed],
          created_count: 0,
          updated_count: @counts[:updated],
          skipped_count: @counts[:skipped],
          error_count: @counts[:errors],
          error_samples: @errors.first(10)
        }
      end

      # update! reemplaza metadata completo; se parte del valor actual para no
      # perder lo que el job dejó registrado al crear la corrida.
      def completion_metadata
        current = @run.metadata.is_a?(Hash) ? @run.metadata.deep_dup : {}
        current.merge({
          "unchanged_count" => @counts[:unchanged],
          "status_changed_count" => @counts[:status_changed],
          "price_changed_count" => @counts[:price_changed],
          "live_price_failed_skus" => @counts[:failed_lookups],
          "batch_size" => @batch_size,
          "max_items" => @max_items
        }.compact)
      end
    end
  end
end
