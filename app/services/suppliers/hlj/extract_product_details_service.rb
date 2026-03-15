# frozen_string_literal: true

module Suppliers
  module Hlj
    class ExtractProductDetailsService
      def initialize(document, source_url:)
        @document = document
        @source_url = source_url
      end

      def call
        details = extract_details
        stock_raw = clean_text(@document.at_css(".product-stock")&.text)

        {
          source_url: @source_url,
          name: product_name(details),
          description_raw: extract_description,
          raw_status: stock_raw,
          canonical_brand: details["manufacturer"] || details["brand"],
          canonical_category: details["category"],
          canonical_series: details["series"],
          canonical_item_type: details["item_type"],
          canonical_release_date: parse_date(details["release_date"]),
          canonical_price: parse_price(@document.at_css("p.price")&.text),
          barcode: details["jan_code"],
          supplier_product_code: details["code"],
          image_urls: extract_image_urls,
          main_image_url: extract_image_urls.first,
          normalized_payload: normalized_payload(details, stock_raw),
          raw_payload: {
            details: details,
            availability_message: availability_message,
            title: product_name(details),
            price_text: clean_text(@document.at_css("p.price")&.text)
          }
        }
      end

      private

      def product_name(details)
        title = clean_text(@document.at_css("h1")&.text)
        title.presence || details["name"]
      end

      def extract_description
        node = @document.at_css("h3 + p, h2 + p, .product-description, .description")
        clean_text(node&.text)
      end

      def extract_details
        @document.css(".product-details li").each_with_object({}) do |detail, acc|
          text = clean_text(detail.text)
          key, value = text.split(":", 2).map { |part| clean_text(part) }
          next if key.blank? || value.blank?

          acc[normalize_key(key)] = value
        end
      end

      def extract_image_urls
        @document.css(".fotorama a[href]").map { |node| node["href"] }.compact_blank.uniq
      end

      def availability_message
        candidate = @document.css("button, .btn, .availability, .stock-message").map { |node| clean_text(node.text) }
                             .find { |text| text&.match?(/ship now|preorder|add to cart/i) }
        candidate.presence
      end

      def normalized_payload(details, stock_raw)
        size_text, weight_text = parse_size_weight(details["item_size_weight"])

        {
          "stock_status_raw" => stock_raw,
          "stock_status_normalized" => Suppliers::Hlj::NormalizeStatusService.new(stock_raw).call,
          "jan_code" => details["jan_code"],
          "code" => details["code"],
          "release_date" => details["release_date"],
          "category" => details["category"],
          "series" => details["series"],
          "item_type" => details["item_type"],
          "manufacturer" => details["manufacturer"],
          "country_of_origin" => details["country_of_origin"],
          "cancellation_deadline" => details["cancellation_deadline"],
          "item_size" => size_text,
          "weight" => weight_text,
          "availability_message" => availability_message
        }.compact
      end

      def parse_size_weight(value)
        return [nil, nil] if value.blank?

        parts = value.split("/").map { |part| clean_text(part) }
        [parts[0], parts[1]]
      end

      def parse_price(text)
        cleaned = clean_text(text)
        return nil if cleaned.blank?

        numeric = cleaned.gsub(/[^\d\.]/, "")
        return nil if numeric.blank?

        numeric.to_d
      end

      def parse_date(value)
        return nil if value.blank?

        Date.parse(value)
      rescue Date::Error, ArgumentError
        nil
      end

      def normalize_key(key)
        key.downcase.gsub(/[()]/, "").gsub(/[^a-z0-9]+/, "_").gsub(/_+/, "_").sub(/_$/, "")
      end

      def clean_text(text)
        text.to_s.gsub(/\s+/, " ").strip.presence
      end
    end
  end
end