# frozen_string_literal: true

module Suppliers
  module Hlj
    class NormalizeStatusService
      MAPPINGS = {
        "in stock" => "in_stock",
        "available to ship now!" => "in_stock",
        "future release" => "future_release",
        "backordered" => "backordered",
        "order stop" => "order_stop",
        "sold out" => "sold_out",
        "discontinued" => "discontinued",
        "low stock" => "low_stock",
        "preorder" => "future_release"
      }.freeze

      # Códigos observados en el endpoint livePrice el 2026-08-02 sobre una
      # muestra de 60 SKUs reales. Solo se mapea lo que se ha observado: un
      # código nuevo se registra y conserva el estado anterior en lugar de
      # inventarle un significado.
      STOCK_STATUS_CODES = {
        "instock" => "in_stock",
        "outofstock" => "out_of_stock",
        "futurerelease" => "future_release",
        "backorder" => "backordered",
        "orderstop" => "order_stop",
        "discontinued" => "discontinued"
      }.freeze

      # HLJ separa las palabras de `availability` con espacios duros (U+00A0),
      # que \s no captura en Ruby. Sin esta normalización "In Stock" nunca
      # coincidía con MAPPINGS y caía al fallback genérico.
      NBSP = " "

      def initialize(raw_status)
        @raw_status = raw_status.to_s.tr(NBSP, " ").strip
      end

      def call
        return nil if @raw_status.blank?

        normalized = @raw_status.downcase.gsub(/\s+/, " ").strip
        MAPPINGS[normalized] || normalized.parameterize.underscore.presence
      end

      # Estado a partir de una entrada de livePrice.
      #
      # Se prefiere el texto de `availability` porque conserva la granularidad
      # que ya vive en la base ("Oct Release" -> oct_release); `stockStatusCode`
      # solo distingue "futurerelease" y aplanaría esos valores. Devuelve nil
      # cuando no hay nada reconocible, para que quien llame conserve el estado
      # actual en vez de borrarlo.
      def self.from_live_price(availability: nil, stock_status_code: nil, logger: Rails.logger)
        from_text = new(availability).call
        return from_text if from_text.present?

        code = stock_status_code.to_s.strip.downcase.presence
        return nil if code.nil?
        return STOCK_STATUS_CODES[code] if STOCK_STATUS_CODES.key?(code)

        logger&.warn("HLJ livePrice: stockStatusCode desconocido #{code.inspect}")
        nil
      end
    end
  end
end
