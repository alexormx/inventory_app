# frozen_string_literal: true

require "json"
require "uri"

module Suppliers
  module TakaraTomyMall
    class ExtractProductDetailsService
      def initialize(document, source_url:, barcode: nil)
        @document = document
        @source_url = source_url
        @barcode = barcode
      end

      def call
        json_ld = extract_json_ld
        image_urls = extract_image_urls(json_ld)
        title = extract_title(json_ld)
        description = extract_description(json_ld)

        {
          source_url: @source_url,
          title: title,
          description: description,
          image_urls: image_urls,
          main_image_url: image_urls.first,
          normalized_payload: {
            "official_title" => title,
            "official_description" => description,
            "barcode" => @barcode.presence,
            "brand" => extract_brand(json_ld),
            "series" => extract_series,
            "material" => extract_material,
            "scale" => extract_scale,
            "release_text" => extract_release_text,
            "additional_image_count" => image_urls.size,
            "specs" => extract_specs
          }.compact,
          raw_payload: {
            json_ld: json_ld,
            title: title,
            description: description,
            specs: extract_specs
          }.compact
        }
      end

      private

      def extract_json_ld
        @extract_json_ld ||= begin
          nodes = @document.css('script[type="application/ld+json"]').map(&:text)
          parsed = nodes.filter_map do |node|
            JSON.parse(node)
          rescue JSON::ParserError
            nil
          end

          parsed.find { |entry| entry.is_a?(Hash) && entry["@type"].to_s.include?("Product") } || {}
        end
      end

      def extract_title(json_ld)
        clean_text(json_ld["name"]) ||
          clean_text(meta_content("og:title")) ||
          clean_text(@document.at_css("h1")&.text) ||
          clean_text(@document.at_css(".product-name, .item_name, .item-detail__title")&.text)
      end

      def extract_description(json_ld)
        clean_text(json_ld["description"]) ||
          clean_text(meta_name_content("description")) ||
          clean_text(@document.at_css(".product-detail__description, .item-description, .txt")&.text)
      end

      def extract_brand(json_ld)
        brand = json_ld["brand"]
        return clean_text(brand["name"]) if brand.is_a?(Hash)

        clean_text(brand)
      end

      def extract_series
        text_from_specs(/シリーズ|series/i)
      end

      def extract_material
        text_from_specs(/材質|material/i)
      end

      def extract_scale
        text_from_specs(/スケール|scale/i)
      end

      def extract_release_text
        text_from_specs(/発売日|release/i)
      end

      def extract_specs
        hash = {}

        @document.css("dt, th").each do |label_node|
          key = clean_text(label_node.text)
          next if key.blank?

          value_node = label_node.xpath("following-sibling::*[1]").first
          value = clean_text(value_node&.text)
          next if value.blank?

          hash[key] = value
        end

        hash
      end

      def extract_image_urls(json_ld)
        images = Array(json_ld["image"]).compact
        images += @document.css("img[src], img[data-src], a[href]").filter_map do |node|
          candidate = node["src"] || node["data-src"] || node["href"]
          next if candidate.blank?
          next unless candidate.match?(/\.(jpg|jpeg|png|webp)(\?|$)/i)

          candidate.start_with?("http") ? candidate : URI.join(@source_url, candidate).to_s
        end

        images.filter_map { |url| clean_text(url) }.uniq
      end

      def text_from_specs(pattern)
        extract_specs.find { |key, _value| key.match?(pattern) }&.last
      end

      def meta_content(property)
        @document.at_css(%(meta[property="#{property}"]))&.[]("content")
      end

      def meta_name_content(name)
        @document.at_css(%(meta[name="#{name}"]))&.[]("content")
      end

      def clean_text(text)
        text.to_s.gsub(/\s+/, " ").strip.presence
      end
    end
  end
end