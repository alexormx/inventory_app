# frozen_string_literal: true

module CatalogPdf
  # Calcula páginas, secciones e índice a partir del conjunto ya filtrado y
  # ordenado. No persiste taxonomía: :series sigue siendo la fuente canónica.
  class Presentation
    PRODUCTS_PER_PAGE = 6
    # Capacidad real de una página de índice. La apaisada se maqueta a dos
    # columnas balanceadas (ver `body.landscape .toc-list { columns: 2 }` en
    # la plantilla), así que 30 entradas caben de sobra en una sola página y
    # el índice solo se parte en dos cuando el catálogo supera esa cifra.
    TOC_ENTRIES_PER_PAGE = { portrait: 18, landscape: 30 }.freeze

    Section = Struct.new(:name, :product_count, :first_page, :anchor, keyword_init: true)
    ProductPage = Struct.new(:items, :section_names, :page_number, :unused_slots, keyword_init: true)

    attr_reader :items, :orientation

    def initialize(items:, orientation:)
      @items = items
      @orientation = orientation == :landscape ? :landscape : :portrait
    end

    def toc_pages
      @toc_pages ||= sections.each_slice(toc_entries_per_page).to_a
    end

    def toc_page_count
      [(section_names.size.to_f / toc_entries_per_page).ceil, 1].max
    end

    def total_pages
      1 + toc_page_count + product_pages.size
    end

    def sections
      @sections ||= section_names.map.with_index do |name, section_index|
        first_index = first_section_indexes.fetch(name)
        Section.new(
          name: name,
          product_count: section_counts.fetch(name),
          first_page: first_product_page + (first_index / PRODUCTS_PER_PAGE),
          anchor: section_anchor(name, section_index)
        )
      end
    end

    def product_pages
      @product_pages ||= items.each_slice(PRODUCTS_PER_PAGE).with_index.map do |page_items, page_index|
        absolute_offset = page_index * PRODUCTS_PER_PAGE
        decorated = page_items.each_with_index.map do |item, item_index|
          index = absolute_offset + item_index
          section_index = section_names.index(section_name(item))
          first_in_section = first_section_indexes.fetch(section_name(item)) == index
          item.merge(section_anchor: (section_anchor(section_name(item), section_index) if first_in_section))
        end

        ProductPage.new(
          items: decorated,
          section_names: page_items.map { |item| section_name(item) }.uniq,
          page_number: first_product_page + page_index,
          unused_slots: PRODUCTS_PER_PAGE - page_items.size
        )
      end
    end

    private

    def first_product_page
      2 + toc_page_count
    end

    def toc_entries_per_page
      TOC_ENTRIES_PER_PAGE.fetch(orientation)
    end

    def section_names
      @section_names ||= items.map { |item| section_name(item) }.uniq
    end

    def section_counts
      @section_counts ||= items.each_with_object(Hash.new(0)) do |item, counts|
        counts[section_name(item)] += 1
      end
    end

    def first_section_indexes
      @first_section_indexes ||= items.each_with_index.with_object({}) do |(item, index), indexes|
        indexes[section_name(item)] ||= index
      end
    end

    def section_name(item)
      item[:series].presence || 'Sin serie'
    end

    def section_anchor(name, index)
      "catalog-section-#{index + 1}-#{name.to_s.parameterize}"
    end
  end
end
