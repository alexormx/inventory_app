# frozen_string_literal: true

require "nokogiri"
require "uri"

module Suppliers
  module TakaraTomyMall
    class FetchDocumentService
      BASE_HEADERS = {
        "User-Agent" => "Mozilla/5.0 (compatible; PasatiemposCatalogBot/1.0)",
        "Accept-Language" => "ja,en-US;q=0.9,en;q=0.8,es-MX;q=0.7"
      }.freeze
      ALLOWED_HOST = /takaratomymall\.jp\z/i
      MAX_REDIRECTS = 3

      Result = Struct.new(:document, :status, :url, keyword_init: true)

      def initialize(url, connection: nil, headers: {})
        @url = url
        @connection = connection || Faraday.new
        @headers = BASE_HEADERS.merge(headers)
      end

      def call
        response, final_url = fetch_with_redirects(@url, MAX_REDIRECTS)
        raise "HTTP #{response.status} for #{final_url}" unless response.success?

        Result.new(document: Nokogiri::HTML(response.body), status: response.status, url: final_url)
      end

      private

      def fetch_with_redirects(url, redirects_left)
        response = @connection.get(url) do |request|
          request.headers.update(@headers)
          request.options.timeout = 25
          request.options.open_timeout = 10
        end

        return [response, url] unless redirect?(response)

        raise "Too many redirects for #{url}" if redirects_left <= 0

        location = response.headers["location"] || response.headers["Location"]
        raise "Redirect without location for #{url}" if location.blank?

        next_url = URI.join(url, location).to_s
        host = URI.parse(next_url).host
        raise "Unexpected redirect host #{host}" unless host&.match?(ALLOWED_HOST)

        fetch_with_redirects(next_url, redirects_left - 1)
      end

      def redirect?(response)
        response.status.to_i >= 300 && response.status.to_i < 400
      end
    end
  end
end