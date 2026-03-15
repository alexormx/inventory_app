# frozen_string_literal: true

module Suppliers
  module TakaraTomyMall
    class BuildUrlService
      BASE_URL = "https://takaratomymall.jp/shop/g/g".freeze

      def initialize(barcode)
        @barcode = barcode.to_s.gsub(/\D/, "")
      end

      def call
        return nil if @barcode.blank?

        "#{BASE_URL}#{@barcode}/"
      end
    end
  end
end