# frozen_string_literal: true

require "cgi"

module Suppliers
  module Hlj
    class SearchQuery
      SEARCH_URL = "https://www.hlj.com/search/".freeze

      GENRE_OPTIONS = [
        "Cars & Bikes", "Gundam", "Science-Fiction", "Action Figures",
        "Anime & Games", "Aircraft", "Military", "Ships", "Railroad",
        "Hobby Supplies", "Radio Control", "Books & Magazines",
        "Puzzles", "Fun Goods", "Apparel", "Stationery", "Dolls"
      ].freeze

      SCALE_OPTIONS = [
        "Non-Scale", "1/6", "1/8", "1/10", "1/12", "1/18", "1/20",
        "1/24", "1/25", "1/32", "1/35", "1/43", "1/48", "1/50",
        "1/64", "1/72", "1/76", "1/87", "1/100", "1/144", "1/150",
        "1/200", "1/350", "1/400", "1/500", "1/700"
      ].freeze

      def initialize(word: nil, makers: [], genre_code: nil, scale: nil, series: nil)
        @word = word.to_s.strip.presence
        @makers = Array(makers).compact_blank
        @genre_code = genre_code.to_s.strip.presence
        @scale = scale.to_s.strip.presence
        @series = series.to_s.strip.presence
      end

      def page_url(page_number = 1)
        params = []
        params << ["Word", @word] if @word.present?
        @makers.each { |maker| params << ["Maker2", maker] }
        params << ["GenreCode2", @genre_code] if @genre_code.present?
        params << ["Scale2", @scale] if @scale.present?
        params << ["Series2", @series] if @series.present?
        params << ["Page", page_number] if page_number.to_i > 1

        query = params.map { |key, value| "#{CGI.escape(key)}=#{CGI.escape(value.to_s)}" }.join("&")
        query.present? ? "#{SEARCH_URL}?#{query}" : "#{SEARCH_URL}?"
      end
    end
  end
end