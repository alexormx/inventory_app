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

      def initialize(raw_status)
        @raw_status = raw_status.to_s.strip
      end

      def call
        return nil if @raw_status.blank?

        normalized = @raw_status.downcase.gsub(/\s+/, " ")
        MAPPINGS[normalized] || normalized.parameterize.underscore
      end
    end
  end
end