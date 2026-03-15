# frozen_string_literal: true

require "nokogiri"

module Suppliers
  module Hlj
    class FetchDocumentService
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

        Result.new(document: Nokogiri::HTML(response.body), status: response.status, url: @url)
      end
    end
  end
end