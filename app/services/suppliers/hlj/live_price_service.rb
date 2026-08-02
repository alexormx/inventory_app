# frozen_string_literal: true

require "json"

module Suppliers
  module Hlj
    # Consulta estado y precio de varios SKUs en una sola petición al endpoint
    # livePrice de HLJ.
    #
    # Existe para que la sincronización diaria no tenga que abrir la página HTML
    # de cada producto: un lote de 50 SKUs sustituye 50 descargas y 50
    # documentos Nokogiri.
    class LivePriceService
      LIVE_PRICE_URL = "https://www.hlj.com/search/livePrice/"

      # HLJ no documenta un máximo de SKUs por petición, así que se usa un lote
      # conservador. Se puede bajar por ENV si el endpoint empieza a truncar.
      DEFAULT_BATCH_SIZE = 50
      REQUEST_TIMEOUT = 15
      OPEN_TIMEOUT = 10

      Result = Struct.new(:prices, :failed_skus, keyword_init: true) do
        # Un SKU ausente no significa "sin precio": puede ser un lote fallido o
        # un producto retirado del feed. Quien consuma esto debe distinguir
        # ambos casos para no borrar datos existentes.
        def fetched?(sku)
          prices.key?(sku)
        end

        def [](sku)
          prices[sku]
        end
      end

      def initialize(connection: nil, batch_size: nil, logger: Rails.logger)
        @connection = connection || Faraday.new
        @batch_size = resolve_batch_size(batch_size)
        @logger = logger
      end

      # Devuelve un Result con los SKUs efectivamente obtenidos. Los lotes que
      # fallan se reportan en failed_skus en lugar de propagar la excepción: una
      # caída parcial no debe abortar toda la sincronización.
      def call(skus)
        cleaned = Array(skus).map { |sku| sku.to_s.strip }.compact_blank.uniq
        return Result.new(prices: {}, failed_skus: []) if cleaned.empty?

        prices = {}
        failed = []

        cleaned.each_slice(@batch_size) do |batch|
          prices.merge!(fetch_batch(batch))
        rescue StandardError => e
          failed.concat(batch)
          @logger.warn("HLJ livePrice batch failed (#{batch.size} SKUs): #{e.message}")
        end

        Result.new(prices: prices, failed_skus: failed)
      end

      private

      def fetch_batch(batch)
        response = @connection.get(LIVE_PRICE_URL) do |req|
          req.headers["User-Agent"] = Suppliers::Hlj::FetchDocumentService::BASE_HEADERS["User-Agent"]
          req.params["item_codes"] = batch.join(",")
          req.options.timeout = REQUEST_TIMEOUT
          req.options.open_timeout = OPEN_TIMEOUT
        end

        raise "HTTP #{response.status}" unless response.success?

        parsed = JSON.parse(response.body.to_s)
        raise "respuesta inesperada: #{parsed.class}" unless parsed.is_a?(Hash)

        parsed.slice(*batch)
      end

      def resolve_batch_size(explicit)
        value = (explicit || ENV["HLJ_LIVE_PRICE_BATCH_SIZE"]).to_i
        value.positive? ? value : DEFAULT_BATCH_SIZE
      end
    end
  end
end
