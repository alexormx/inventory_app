# frozen_string_literal: true

require "nokogiri"

module Suppliers
  module Hlj
    class FetchDocumentService
      CHALLENGE_TITLES = ["Human Verification"].freeze
      BASE_HEADERS = {
        "User-Agent" => "Mozilla/5.0 (compatible; PasatiemposCatalogBot/1.0)",
        "Accept-Language" => "en-US,en;q=0.9,es-MX;q=0.8"
      }.freeze

      Result = Struct.new(:document, :status, :url, keyword_init: true)

      def initialize(url, connection: nil, headers: {})
        @url = url
        @connection = connection || Faraday.new
        @headers = BASE_HEADERS.merge(headers)
      end

      def call
        response = @connection.get(@url) do |request|
          request.headers.update(@headers)
          request.options.timeout = 20
          request.options.open_timeout = 10
        end

        raise "HTTP #{response.status} for #{@url}" unless response.success?

        document = Nokogiri::HTML(response.body)
        raise "HLJ blocked the request with human verification for #{@url}" if challenge_page?(document)

        Result.new(document: document, status: response.status, url: @url)
      end

      private

      def challenge_page?(document)
        title = document.at_css("title")&.text&.strip
        body_text = document.at_css("body")&.text.to_s

        CHALLENGE_TITLES.include?(title) || body_text.match?(/captcha puzzle|enable javascript|human verification/i)
      end
    end
  end
end