# frozen_string_literal: true

require "cgi"

module Suppliers
  module Hlj
    class SearchQuery
      SEARCH_URL = "https://www.hlj.com/search/".freeze

      def initialize(word: nil, makers: [], genre_code: nil)
        @word = word.to_s.strip.presence
        @makers = Array(makers).compact_blank
        @genre_code = genre_code.to_s.strip.presence
      end

      def page_url(page_number = 1)
        params = []
        params << ["Word", @word] if @word.present?
        @makers.each { |maker| params << ["Maker2", maker] }
        params << ["GenreCode2", @genre_code] if @genre_code.present?
        params << ["Page", page_number] if page_number.to_i > 1

        query = params.map { |key, value| "#{CGI.escape(key)}=#{CGI.escape(value.to_s)}" }.join("&")
        query.present? ? "#{SEARCH_URL}?#{query}" : "#{SEARCH_URL}?"
      end
    end
  end
end