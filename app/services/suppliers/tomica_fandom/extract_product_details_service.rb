# frozen_string_literal: true

require "nokogiri"

module Suppliers
  module TomicaFandom
    class ExtractProductDetailsService
      def initialize(page_result)
        @page_result = page_result
        @document = Nokogiri::HTML.fragment(page_result.html)
      end

      def call
        {
          source_url: @page_result.url,
          title: clean_text(@page_result.display_title.presence || @page_result.page_title),
          overview: section_text("Overview"),
          description: section_text("Description"),
          trivia: section_list("Trivia"),
          image_urls: extract_image_urls,
          main_image_url: extract_image_urls.first,
          normalized_payload: normalized_payload,
          raw_payload: {
            page_title: @page_result.page_title,
            display_title: @page_result.display_title,
            images: @page_result.images,
            overview: section_text("Overview"),
            description: section_text("Description"),
            trivia: section_list("Trivia")
          }.compact
        }
      end

      private

      def normalized_payload
        overview = section_text("Overview")
        description = section_text("Description")

        {
          "official_title" => clean_text(@page_result.display_title.presence || @page_result.page_title),
          "overview" => overview,
          "description" => description,
          "trivia" => section_list("Trivia"),
          "scale" => extract_scale(description),
          "release_text" => extract_release_text(overview),
          "retired_text" => extract_retired_text(overview),
          "replaced" => extract_link_title(overview, /replaced the/i),
          "succeeded_by" => extract_link_title(overview, /succeeded by/i),
          "image_count" => extract_image_urls.size
        }.compact
      end

      def extract_image_urls
        @extract_image_urls ||= @document.css("img[src], a.image[href]").filter_map do |node|
          candidate = node["src"] || node["href"]
          next if candidate.blank?
          next unless image_candidate?(candidate)

          candidate
        end.uniq
      end

      def image_candidate?(candidate)
        candidate.match?(/\.(jpg|jpeg|png|webp)(\?|$)/i) || candidate.include?("static.wikia.nocookie.net")
      end

      def section_text(title)
        nodes = section_nodes(title)
        return nil if nodes.empty?

        clean_text(nodes.map(&:text).join(" "))
      end

      def section_list(title)
        nodes = section_nodes(title)
        nodes.flat_map { |node| node.css("li").map { |item| clean_text(item.text) } }.compact_blank.uniq
      end

      def section_nodes(title)
        headline = @document.at_css(%(span.mw-headline[id="#{title}"]))
        return [] unless headline

        nodes = []
        sibling = headline.parent&.next_sibling

        while sibling
          break if sibling.element? && sibling.name.match?(/h1|h2/)

          nodes << sibling if sibling.element?
          sibling = sibling.next_sibling
        end

        nodes
      end

      def extract_scale(text)
        text.to_s[/\b\d+\/\d+\b/]
      end

      def extract_release_text(text)
        text.to_s[/released\s+([^\.]+)/i, 1]&.strip
      end

      def extract_retired_text(text)
        text.to_s[/retired\s+([^\.]+)/i, 1]&.strip
      end

      def extract_link_title(text, pattern)
        return nil if text.blank?

        link = @document.css("a[title]").find { |node| node.parent&.text.to_s.match?(pattern) }
        clean_text(link&.[]("title"))
      end

      def clean_text(text)
        text.to_s.gsub(/\s+/, " ").strip.presence
      end
    end
  end
end