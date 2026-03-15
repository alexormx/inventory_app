# frozen_string_literal: true

module Suppliers
  module TomicaFandom
    class BuildPageTitleService
      def initialize(catalog_item)
        @catalog_item = catalog_item
      end

      def call
        variants.uniq
      end

      private

      def variants
        name = normalized_name
        return [] if name.blank?

        compact_variants = []
        compact_variants << name
        compact_variants << name.sub(/\ATomica\s+/i, "")

        if (match = name.match(/\A(?:Tomica\s+)?No\.?\s*(\d+)\s+(.+)\z/i))
          compact_variants << "No. #{match[1]} #{match[2]}"
          compact_variants << "Tomica No. #{match[1]} #{match[2]}"
        end

        compact_variants.map { |value| value.to_s.gsub(/\s+/, " ").strip }.reject(&:blank?)
      end

      def normalized_name
        @normalized_name ||= begin
          value = @catalog_item.canonical_name.to_s.dup
          value = value.gsub(/\u00A0/, " ")
          value = value.gsub(/\ANo\.?\s*(\d+)/i, 'No. \1')
          value.gsub(/\s+/, " ").strip
        end
      end
    end
  end
end