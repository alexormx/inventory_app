# frozen_string_literal: true

module Products
  module Enrichment
    # Quita identificadores internos de lo que la IA genera para la tienda. El SKU
    # y el código del proveedor no deben verse en ninguna superficie pública, y el
    # código de barras no le sirve al comprador. De una lista (características,
    # palabras clave) se tira la entrada completa; de la descripción, sólo la
    # oración que lo menciona.
    class ScrubIdentifiersService
      LABELS = /\b(sku|c[óo]digos? de (?:barras|proveedor)|jan|ean|upc)\b/i
      MIN_LENGTH = 4

      def initialize(product)
        @product = product
        @removed = false
      end

      def removed?
        @removed
      end

      def clean_list(items)
        Array(items).map(&:to_s).reject { |item| mentions?(item) && (@removed = true) }
      end

      def clean_text(text)
        text.to_s.split(/\n{2,}/).map { |paragraph| clean_paragraph(paragraph) }.compact_blank.join("\n\n")
      end

      private

      def clean_paragraph(paragraph)
        sentences = paragraph.strip.split(/(?<=[.!?])\s+/)
        kept = sentences.reject { |sentence| mentions?(sentence) && (@removed = true) }
        kept.join(' ')
      end

      def mentions?(text)
        downcased = text.downcase
        text.match?(LABELS) || identifiers.any? { |code| downcased.include?(code) }
      end

      def identifiers
        @identifiers ||= [@product.product_sku, @product.supplier_product_code, @product.barcode]
                         .map { |code| code.to_s.strip.downcase }
                         .select { |code| code.length >= MIN_LENGTH }
                         .uniq
      end
    end
  end
end
