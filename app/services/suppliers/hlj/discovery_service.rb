# frozen_string_literal: true

module Suppliers
  module Hlj
    class DiscoveryService
      class StopRequested < StandardError; end

      SEARCH_URL = Suppliers::Hlj::SearchQuery::SEARCH_URL

      # Qué tan lejos se llega por producto:
      #   all      -> descarga la página de detalle de cada ítem (sync completa)
      #   new_only -> solo para SKUs que aún no existen en el catálogo
      #   none     -> nunca; únicamente estado y precio del listado
      DETAIL_POLICIES = %w[all new_only none].freeze
      DEFAULT_DETAIL_POLICY = "all"

      # Si HLJ reporta muchas más páginas de las esperadas es señal de que un
      # filtro remoto dejó de aplicarse. Se registra y se recorta en vez de
      # recorrer el catálogo entero.
      DEFAULT_PAGE_ANOMALY_THRESHOLD = 20

      # Cota dura de tiempo de pared. Sin ella, un filtro roto convierte la
      # corrida en un scrape de horas dentro del dyno web. El default es el
      # techo del sync completo semanal, que por definición necesita recorrer
      # todo; los jobs diarios pasan un presupuesto mucho más corto.
      DEFAULT_MAX_DURATION_SECONDS = 3600
      DAILY_MAX_DURATION_SECONDS = 900

      # El progreso se escribe cada N ítems en vez de en cada uno: la versión
      # anterior hacía dos round trips a la base por producto.
      PROGRESS_FLUSH_INTERVAL = 25

      Counters = Struct.new(:processed, :created, :updated, :unchanged, :skipped,
                            :status_changed, :price_changed, :detail_fetches) do
        def initialize(*)
          super
          members.each { |member| self[member] ||= 0 }
        end
      end

      def initialize(max_pages: nil, max_items: nil, word: nil, makers: [], genre_codes: [], scales: [], series: nil,
                     date_added_within_days: nil, date_arrivals_within_days: nil, review_feed: nil,
                     fetch_detail: nil, detail_policy: nil, delay_seconds: 0, connection: nil, run: nil,
                     page_anomaly_threshold: nil, max_duration_seconds: DEFAULT_MAX_DURATION_SECONDS,
                     live_price_service: nil, logger: Rails.logger)
        @max_pages = max_pages
        @max_items = max_items
        @query = Suppliers::Hlj::SearchQuery.new(
          word: word,
          makers: makers,
          genre_codes: genre_codes,
          scales: scales,
          series: series,
          date_added_within_days: date_added_within_days,
          date_arrivals_within_days: date_arrivals_within_days
        )
        @review_feed = review_feed.presence
        @detail_policy = resolve_detail_policy(detail_policy, fetch_detail)
        @delay_seconds = delay_seconds.to_f
        @connection = connection || Faraday.new
        @run = run || SupplierSyncRun.create!(source: "hlj", mode: "weekly_discovery", status: "queued")
        @page_anomaly_threshold = (page_anomaly_threshold || DEFAULT_PAGE_ANOMALY_THRESHOLD).to_i
        @max_duration_seconds = max_duration_seconds&.to_i
        @live_price_service = live_price_service || Suppliers::Hlj::LivePriceService.new(connection: @connection, logger: logger)
        @logger = logger
        @errors = []
      end

      def call
        @run.start! if @run.status == "queued"
        @started_at = Time.current
        counters = Counters.new
        initialize_progress!

        total_pages.times do |index|
          check_stop_requested!(force: true)
          break if time_budget_exceeded?

          page_number = index + 1
          items = fetch_page_items(page_number)
          flush_progress(counters, page_number: page_number, page_item_index: 0, page_item_count: items.size)

          process_page(items, counters, page_number)

          break if reached_max_items?(counters.processed)
        end

        @run.complete!(**run_counts(counters), metadata: completion_metadata(counters))
      rescue StopRequested
        @run.cancel!(**run_counts(counters), metadata: completion_metadata(counters).merge(cancellation_metadata))
      rescue StandardError => e
        @run.fail!(e.message)
        raise
      end

      private

      def resolve_detail_policy(detail_policy, fetch_detail)
        policy = detail_policy.presence&.to_s
        policy ||= (fetch_detail ? "all" : "none") unless fetch_detail.nil?
        policy ||= DEFAULT_DETAIL_POLICY

        return policy if DETAIL_POLICIES.include?(policy)

        raise ArgumentError, "detail_policy inválido: #{policy.inspect}"
      end

      def process_page(items, counters, page_number)
        existing_by_sku = existing_items_by_sku(items)
        seen_ids = []

        items.each_with_index do |item, item_index|
          check_stop_requested!
          break if time_budget_exceeded?

          existing = existing_by_sku[item[:external_sku]]
          apply_item(item, existing, counters)
          seen_ids << existing.id if existing
          counters.processed += 1

          flush_progress(counters, page_number: page_number, page_item_index: item_index + 1,
                                   page_item_count: items.size, throttle: true)
          sleep(@delay_seconds) if @delay_seconds.positive?
          break if reached_max_items?(counters.processed)
        rescue StopRequested
          raise
        rescue StandardError => e
          counters.skipped += 1
          record_error(item, e)
        end

        touch_seen!(seen_ids)
        flush_progress(counters, page_number: page_number, page_item_index: items.size, page_item_count: items.size)
      end

      def apply_item(item, existing, counters)
        if existing && !fetch_detail_for?(existing)
          apply_listing_state(item, existing, counters)
        else
          counters.detail_fetches += 1 if fetch_detail_for?(existing)
          apply_full_import(item, counters)
        end
      end

      # Camino ligero: el producto ya existe y no se bajó su detalle, así que
      # solo puede moverse estado y precio. Reescribir el resto con datos del
      # listado degradaría nombre, imágenes y descripción ya capturados.
      def apply_listing_state(item, existing, counters)
        result = Suppliers::Catalog::UpdateListingStateService.new(
          catalog_item: existing,
          status: live_status_for(item),
          price: item[:jpy_price] || item[:jpy_special_price],
          currency: (item[:jpy_price] || item[:jpy_special_price]) ? "JPY" : nil,
          review_feed: @review_feed,
          touch_timestamps: false,
          now: @now
        ).call

        tally_change(result, counters, created: false)
      end

      def apply_full_import(item, counters)
        result = import_item(item)
        tally_change(result, counters, created: result.created)
      end

      def tally_change(result, counters, created:)
        if created
          counters.created += 1
        elsif result.changed
          counters.updated += 1
        else
          counters.unchanged += 1
        end

        counters.status_changed += 1 if result.status_changed
        counters.price_changed += 1 if result.price_changed
      end

      def fetch_detail_for?(existing)
        case @detail_policy
        when "all" then true
        when "new_only" then existing.nil?
        else false
        end
      end

      # Una sola consulta por página en vez de un find_by por producto.
      def existing_items_by_sku(items)
        skus = items.filter_map { |item| item[:external_sku].presence }
        return {} if skus.empty?

        SupplierCatalogItem.where(source_key: "hlj", external_sku: skus).index_by(&:external_sku)
      end

      # Refresco agrupado de las marcas de "lo vi en esta pasada": un UPDATE por
      # página en lugar de uno por producto sin cambios.
      def touch_seen!(ids)
        return if ids.empty?

        SupplierCatalogItem.where(id: ids).update_all(last_seen_at: @now, source_last_synced_at: @now)
      end

      def live_status_for(item)
        Suppliers::Hlj::NormalizeStatusService.from_live_price(
          availability: item[:availability],
          stock_status_code: item[:stock_status],
          logger: @logger
        )
      end

      def total_pages
        @total_pages ||= begin
          value = [remote_total_pages, 1].max
          @max_pages.present? ? [value, @max_pages].min : value
        end
      end

      def remote_total_pages
        return @remote_total_pages if defined?(@remote_total_pages)

        @first_page_doc = fetch_document(page_url(1))
        last_page = @first_page_doc.at_css(".pages li:nth-last-child(2)")&.text.to_i
        @remote_total_pages = last_page.positive? ? last_page : 1
      end

      def page_anomaly?
        remote_total_pages > @page_anomaly_threshold
      end

      def fetch_page_items(page_number)
        doc = if page_number == 1 && @first_page_doc
                @first_page_doc.tap { @first_page_doc = nil }
              else
                fetch_document(page_url(page_number))
              end

        items = Suppliers::Hlj::ExtractListItemsService.new(doc).call
        enrich_with_live_prices!(items)
        items
      end

      def initialize_progress!
        @now = Time.current

        if page_anomaly?
          @logger.warn(
            "HLJ discovery: #{remote_total_pages} páginas reportadas supera el umbral " \
            "#{@page_anomaly_threshold}; se recorren #{total_pages}"
          )
        end

        @run.update_progress!(
          counts: { processed_count: 0, created_count: 0, updated_count: 0, skipped_count: 0, error_count: 0 },
          metadata: progress_metadata(page_number: 1, page_item_index: 0, page_item_count: 0).merge(
            "progress_started_at" => @now.iso8601,
            "detail_policy" => @detail_policy,
            "remote_total_pages" => remote_total_pages,
            "page_count_anomaly" => page_anomaly?
          )
        )
      end

      def flush_progress(counters, page_number:, page_item_index:, page_item_count:, throttle: false)
        return if throttle && (page_item_index % PROGRESS_FLUSH_INTERVAL).nonzero?

        @run.update_progress!(
          counts: run_counts(counters).slice(:processed_count, :created_count, :updated_count,
                                             :skipped_count, :error_count),
          metadata: progress_metadata(page_number: page_number, page_item_index: page_item_index,
                                      page_item_count: page_item_count)
        )
      end

      def progress_metadata(page_number:, page_item_index:, page_item_count:)
        {
          "progress_current_page" => page_number,
          "progress_page_item_index" => page_item_index,
          "progress_page_item_count" => page_item_count,
          "progress_total_pages" => total_pages,
          "progress_total_items" => @max_items
        }.compact
      end

      def run_counts(counters)
        {
          processed_count: counters.processed,
          created_count: counters.created,
          updated_count: counters.updated,
          skipped_count: counters.skipped,
          error_count: @errors.size,
          error_samples: @errors.first(10)
        }
      end

      # update! reemplaza metadata completo, así que se parte del valor actual
      # para no perder el progreso ya registrado.
      def completion_metadata(counters)
        current = @run.metadata.is_a?(Hash) ? @run.metadata.deep_dup : {}
        current.merge({
          "detail_policy" => @detail_policy,
          "detail_fetch_count" => counters.detail_fetches,
          "unchanged_count" => counters.unchanged,
          "status_changed_count" => counters.status_changed,
          "price_changed_count" => counters.price_changed,
          "remote_total_pages" => remote_total_pages,
          "pages_traversed" => total_pages,
          "max_pages" => @max_pages,
          "max_items" => @max_items,
          "page_count_anomaly" => page_anomaly?,
          "duration_seconds" => @started_at ? (Time.current - @started_at).round : nil,
          "stopped_reason" => @stopped_reason
        }.compact)
      end

      def page_url(page_number)
        @query.page_url(page_number)
      end

      def import_item(item)
        payload = listing_payload(item)
        detail_fetched = false

        if @detail_policy != "none"
          detail_doc = fetch_document(item[:source_url])
          detail_payload = Suppliers::Hlj::ExtractProductDetailsService.new(detail_doc, source_url: item[:source_url]).call
          payload = merge_payloads(payload, detail_payload)
          detail_fetched = true
        end

        jpy_price = item[:jpy_price] || item[:jpy_special_price]

        Suppliers::Catalog::ImportCatalogItemService.new(
          source: "hlj",
          external_sku: item[:external_sku],
          name: payload[:name] || item[:name],
          source_url: payload[:source_url] || item[:source_url],
          raw_status: payload[:raw_status].presence || item[:availability],
          barcode: payload[:barcode],
          supplier_product_code: payload[:supplier_product_code],
          canonical_brand: payload[:canonical_brand],
          canonical_category: payload[:canonical_category],
          canonical_series: payload[:canonical_series],
          canonical_item_type: payload[:canonical_item_type],
          canonical_release_date: payload[:canonical_release_date],
          canonical_price: jpy_price || payload[:canonical_price],
          currency: jpy_price ? "JPY" : "MXN",
          description_raw: payload[:description_raw],
          image_urls: payload[:image_urls],
          main_image_url: payload[:main_image_url],
          review_feed: @review_feed,
          full_sync: detail_fetched,
          normalized_payload: payload[:normalized_payload],
          raw_payload: payload[:raw_payload].merge(jpy_price: item[:jpy_price], jpy_special_price: item[:jpy_special_price]).compact
        ).call
      rescue StandardError => e
        @logger.warn("HLJ detail fallback for #{item[:external_sku]}: #{e.message}")

        Suppliers::Catalog::ImportCatalogItemService.new(
          source: "hlj",
          external_sku: item[:external_sku],
          name: item[:name],
          source_url: item[:source_url],
          raw_status: item[:availability],
          canonical_price: item[:jpy_price] || item[:jpy_special_price] || parse_listing_price(item[:listing_price_text]),
          currency: item[:jpy_price] ? "JPY" : "MXN",
          image_urls: Array(item[:listing_image_url]).compact,
          main_image_url: item[:listing_image_url],
          review_feed: @review_feed,
          full_sync: false,
          normalized_payload: {},
          raw_payload: { listing_price_text: item[:listing_price_text], detail_error: e.message, jpy_price: item[:jpy_price], jpy_special_price: item[:jpy_special_price] }.compact
        ).call
      end

      def fetch_document(url)
        Suppliers::Hlj::FetchDocumentService.new(url, connection: @connection).call.document
      end

      # El reload por producto costaba una consulta por ítem. Se consulta al
      # inicio de cada página y cada PROGRESS_FLUSH_INTERVAL ítems.
      def check_stop_requested!(force: false)
        @stop_checks = (@stop_checks || 0) + 1
        return unless force || (@stop_checks % PROGRESS_FLUSH_INTERVAL).zero?

        raise StopRequested if @run.reload.stop_requested?
      end

      def time_budget_exceeded?
        return false if @max_duration_seconds.blank? || @started_at.blank?
        return false if Time.current - @started_at < @max_duration_seconds

        @stopped_reason ||= "max_duration_seconds"
        @logger.warn("HLJ discovery: se alcanzó el límite de #{@max_duration_seconds}s; se detiene el recorrido")
        true
      end

      def record_error(item, error)
        @errors << "#{item[:external_sku]}: #{error.message}"
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
        { "cancelled_by_user" => true, "cancelled_at" => Time.current.iso8601 }
      end

      def reached_max_items?(processed)
        @max_items.present? && processed >= @max_items
      end

      # Un SKU ausente en la respuesta no se toca: puede ser un lote fallido, y
      # escribir nil borraría estado y precio buenos.
      def enrich_with_live_prices!(items)
        skus = items.filter_map { |item| item[:external_sku].presence }
        return if skus.empty?

        result = @live_price_service.call(skus)

        items.each do |item|
          info = result[item[:external_sku]]
          next unless info.is_a?(Hash)

          item[:jpy_price] = info["JPYprice"]
          item[:jpy_special_price] = info["JPYspecial_price"]
          item[:stock_status] = info["stockStatusCode"]
          item[:availability] = info["availability"]
        end
      end
    end
  end
end
