# frozen_string_literal: true

require "nokogiri"
require "uri"

module Suppliers
  module TakaraTomyMall
    class FetchDocumentService
      BASE_HEADERS = {
        "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language" => "ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7",
        "Sec-Fetch-Dest" => "document",
        "Sec-Fetch-Mode" => "navigate",
        "Sec-Fetch-Site" => "none",
        "Sec-Fetch-User" => "?1",
        "Upgrade-Insecure-Requests" => "1"
      }.freeze
      ALLOWED_HOSTS = /\A(takaratomymall\.jp|takaratomy\.queue-it\.net)\z/i
      MAX_REDIRECTS = 6
      MAX_RETRIES = 2
      TIMEOUT = 10
      OPEN_TIMEOUT = 6

      Result = Struct.new(:document, :status, :url, keyword_init: true)

      def initialize(url, connection: nil, headers: {})
        @url = url
        @connection = connection || build_connection
        @headers = BASE_HEADERS.merge(headers)
        @cookie_jar = {}
      end

      def call
        attempts = 0
        last_error = nil

        while attempts < MAX_RETRIES
          attempts += 1
          @cookie_jar = {}
          begin
            response, final_url = fetch_with_redirects(@url, MAX_REDIRECTS)
            raise "HTTP #{response.status} for #{final_url}" unless response.success?

            return Result.new(document: Nokogiri::HTML(response.body), status: response.status, url: final_url)
          rescue Net::ReadTimeout, Net::OpenTimeout, Faraday::TimeoutError => e
            last_error = e
            sleep(2) if attempts < MAX_RETRIES
          end
        end

        raise last_error
      end

      private

      def build_connection
        Faraday.new do |f|
          f.adapter :net_http
        end
      end

      def fetch_with_redirects(url, redirects_left)
        response = @connection.get(url) do |request|
          request.headers.update(@headers)
          request.headers["Cookie"] = cookie_header_for(url) if @cookie_jar.any?
          request.options.timeout = TIMEOUT
          request.options.open_timeout = OPEN_TIMEOUT
        end

        store_cookies(url, response)

        return [response, url] unless redirect?(response)

        raise "Too many redirects for #{url}" if redirects_left <= 0

        location = response.headers["location"] || response.headers["Location"]
        raise "Redirect without location for #{url}" if location.blank?

        next_url = URI.join(url, location).to_s
        host = URI.parse(next_url).host
        raise "Unexpected redirect host #{host}" unless host&.match?(ALLOWED_HOSTS)

        fetch_with_redirects(next_url, redirects_left - 1)
      end

      def redirect?(response)
        response.status.to_i >= 300 && response.status.to_i < 400
      end

      def store_cookies(url, response)
        set_cookies = response.headers.to_a.select { |k, _| k.downcase == "set-cookie" }
        return if set_cookies.empty?

        # Faraday may collapse multiple Set-Cookie into one comma-separated or newline-separated string
        raw = response.headers["set-cookie"].to_s
        raw.split(/\n/).each do |cookie_str|
          parts = cookie_str.strip.split(";").map(&:strip)
          next if parts.empty?

          name_value = parts.first
          name, value = name_value.split("=", 2)
          next if name.blank?

          domain = extract_cookie_domain(parts) || URI.parse(url).host
          @cookie_jar[domain] ||= {}
          @cookie_jar[domain][name.strip] = value.to_s
        end
      end

      def extract_cookie_domain(parts)
        domain_part = parts.find { |p| p.downcase.start_with?("domain=") }
        return nil unless domain_part

        domain_part.split("=", 2).last.strip.sub(/\A\./, "")
      end

      def cookie_header_for(url)
        host = URI.parse(url).host
        cookies = {}

        @cookie_jar.each do |domain, pairs|
          cookies.merge!(pairs) if host == domain || host.end_with?(".#{domain}") || domain.end_with?(".#{host}")
        end

        cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
      end
    end
  end
end