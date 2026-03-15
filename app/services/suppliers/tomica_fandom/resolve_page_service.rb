# frozen_string_literal: true

require "nokogiri"

module Suppliers
  module TomicaFandom
    class ResolvePageService
      def initialize(catalog_item, connection: nil)
        @catalog_item = catalog_item
        @connection = connection
      end

      def call
        direct_candidates.each do |title|
          page = fetch_page(title)
          return page if page
        end

        release_year_candidates.each do |year_page_title|
          year_page = fetch_page(year_page_title)
          next unless year_page

          matched_title = find_linked_page_title(year_page.html)
          next if matched_title.blank?

          page = fetch_page(matched_title)
          return page if page
        end

        raise "No se encontró una página de Tomica Fandom para #{@catalog_item.canonical_name}"
      end

      private

      def direct_candidates
        Suppliers::TomicaFandom::BuildPageTitleService.new(@catalog_item).call
      end

      def release_year_candidates
        years = []
        years << @catalog_item.canonical_release_date.year if @catalog_item.canonical_release_date.present?
        years.compact.uniq.map { |year| "Tomica #{year}" }
      end

      def fetch_page(title)
        Suppliers::TomicaFandom::FetchPageService.new(title, connection: @connection).call
      rescue StandardError
        nil
      end

      def find_linked_page_title(html)
        document = Nokogiri::HTML.fragment(html)
        candidates = document.css("a[title]").map { |node| node["title"].to_s.strip.presence }.compact.uniq
        candidates.find { |title| exact_match?(title) } || candidates.find { |title| fuzzy_match?(title) }
      end

      def exact_match?(title)
        normalize(title) == normalize(primary_title)
      end

      def fuzzy_match?(title)
        title_norm = normalize(title)
        name_norm = normalize(primary_title)
        title_norm.include?(name_norm) || name_norm.include?(title_norm)
      end

      def primary_title
        direct_candidates.first.to_s
      end

      def normalize(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
      end
    end
  end
end