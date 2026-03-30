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

      MAKER_OPTIONS = [
        "Takara Tomy", "Tomy", "Tomytec", "Takara Tomy A.R.T.S",
        "Bandai", "Tamiya", "Hasegawa", "Aoshima", "Fujimi",
        "Good Smile Company", "Kotobukiya", "Max Factory", "Kaiyodo",
        "MegaHouse", "Medicom", "Hot Toys", "Sentinel",
        "Hobby Japan", "Ignition Model", "Kyosho",
        "Ebbro", "F-Toys", "Revell", "Fine Molds",
        "Platz", "Dragon", "Meng", "Trumpeter"
      ].freeze

      def initialize(word: nil, makers: [], genre_codes: [], scales: [], series: nil,
                     date_added_within_days: nil, date_arrivals_within_days: nil)
        @word = word.to_s.strip.presence
        @makers = Array(makers).compact_blank
        @genre_codes = Array(genre_codes).compact_blank
        @scales = Array(scales).compact_blank
        @series = series.to_s.strip.presence
        @date_added_within_days = positive_integer_or_nil(date_added_within_days)
        @date_arrivals_within_days = positive_integer_or_nil(date_arrivals_within_days)
      end

      def page_url(page_number = 1)
        params = []
        params << ["Word", @word] if @word.present?
        @makers.each { |maker| params << ["Maker2", maker] }
        @genre_codes.each { |gc| params << ["GenreCode2", gc] }
        @scales.each { |s| params << ["Scale2", s] }
        params << ["Series2", @series] if @series.present?
        params << ["dateAdded2", "-#{@date_added_within_days}"] if @date_added_within_days.present?
        params << ["dateArrivals", "-#{@date_arrivals_within_days}"] if @date_arrivals_within_days.present?
        params << ["Page", page_number] if page_number.to_i > 1

        query = params.map { |key, value| "#{CGI.escape(key)}=#{CGI.escape(value.to_s)}" }.join("&")
        query.present? ? "#{SEARCH_URL}?#{query}" : "#{SEARCH_URL}?"
      end

      private

      def positive_integer_or_nil(value)
        number = value.to_i
        number.positive? ? number : nil
      end
    end
  end
end