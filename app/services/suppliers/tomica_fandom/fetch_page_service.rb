# frozen_string_literal: true

require "json"

module Suppliers
  module TomicaFandom
    class FetchPageService
      API_URL = "https://tomica.fandom.com/api.php".freeze
      BASE_HEADERS = {
        "User-Agent" => "Mozilla/5.0 (compatible; PasatiemposCatalogBot/1.0)",
        "Accept-Language" => "en-US,en;q=0.9,es-MX;q=0.8"
      }.freeze

      Result = Struct.new(:page_title, :page_id, :display_title, :html, :images, :url, keyword_init: true)

      def initialize(page_title, connection: nil, headers: {})
        @page_title = page_title.to_s.strip
        @connection = connection || Faraday.new
        @headers = BASE_HEADERS.merge(headers)
      end

      def call
        raise ArgumentError, "page_title is required" if @page_title.blank?

        response = @connection.get(API_URL) do |request|
          request.headers.update(@headers)
          request.options.timeout = 20
          request.options.open_timeout = 10
          request.params.update(
            action: "parse",
            page: @page_title,
            prop: "text|images|displaytitle",
            format: "json"
          )
        end

        raise "HTTP #{response.status} for #{@page_title}" unless response.success?

        body = JSON.parse(response.body)
        raise body.dig("error", "info") || "Page #{@page_title} not found" if body["error"].present?

        parse = body.fetch("parse")
        Result.new(
          page_title: parse["title"],
          page_id: parse["pageid"],
          display_title: parse["displaytitle"],
          html: parse.dig("text", "*"),
          images: Array(parse["images"]),
          url: "https://tomica.fandom.com/wiki/#{CGI.escape(parse["title"].to_s.tr(" ", "_"))}"
        )
      end
    end
  end
end