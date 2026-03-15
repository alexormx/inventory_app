# frozen_string_literal: true

module Products
  module Enrichment
    # Normalizes AI-generated attributes to match expected types from the
    # CategoryAttributeTemplate schema. Handles booleans, dates, and strings.
    class NormalizeAttributesService
      def initialize(raw_attributes, template)
        @raw = raw_attributes || {}
        @template = template
      end

      def call
        return @raw unless @template

        normalized = {}
        @template.attributes_schema.each do |attr_def|
          key = attr_def["key"]
          value = @raw[key]
          type = attr_def["type"]

          normalized[key] = normalize_value(value, type)
        end

        # Preserve any extra keys the AI returned that aren't in the template
        @raw.each do |key, value|
          normalized[key] = value unless normalized.key?(key)
        end

        normalized
      end

      private

      def normalize_value(value, type)
        return nil if value.nil? || value.to_s.strip.empty? || value.to_s.downcase == "null"

        case type
        when "boolean"
          normalize_boolean(value)
        when "date"
          normalize_date(value)
        when "string"
          value.to_s.strip
        else
          value.to_s.strip
        end
      end

      def normalize_boolean(value)
        case value.to_s.downcase.strip
        when "true", "sí", "si", "yes", "1"
          "true"
        when "false", "no", "0"
          "false"
        else
          value.to_s.strip
        end
      end

      def normalize_date(value)
        Date.parse(value.to_s).iso8601
      rescue Date::Error, ArgumentError
        value.to_s.strip
      end
    end
  end
end
