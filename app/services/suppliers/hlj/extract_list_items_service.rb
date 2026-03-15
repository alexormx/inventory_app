# frozen_string_literal: true

module Suppliers
  module Hlj
    class ExtractListItemsService
      BASE_URL = "https://www.hlj.com".freeze

      def initialize(document)
        @document = document
      end

      def call
        @document.css("div.search-widget-block").filter_map do |block|
          name = block.at_css(".product-item-name")&.text&.strip
          href = block.at_css("a")&.[]("href")
          span_id = block.at_css(".price span")&.[]("id")
          external_sku = span_id.to_s.split("_").first.presence

          next if name.blank? || href.blank? || external_sku.blank?

          {
            external_sku: external_sku,
            name: name,
            source_url: absolute_url(href),
            listing_price_text: block.at_css(".price")&.text&.gsub(/\s+/, " ")&.strip,
            listing_image_url: absolute_url(block.at_css("img")&.[]("src"))
          }
        end
      end

      private

      def absolute_url(href)
        return nil if href.blank?
        return "https:#{href}" if href.start_with?("//")
        return href if href.start_with?("http://", "https://")

        "#{BASE_URL}#{href}"
      end
    end
  end
end