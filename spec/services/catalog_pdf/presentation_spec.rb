# frozen_string_literal: true

require 'rails_helper'

# El índice (TOC) del catálogo apaisado tiene que caber en UNA página con dos
# columnas balanceadas, y todos los números de página se derivan de la
# estructura real del documento (nunca se hardcodean).
RSpec.describe CatalogPdf::Presentation do
  LANDSCAPE_TOC_CAPACITY = described_class::TOC_ENTRIES_PER_PAGE.fetch(:landscape)

  def items_for(series_names, per_series: 1)
    series_names.flat_map do |name|
      Array.new(per_series) do |i|
        { series: name, name: "#{name} #{i}", code: "#{name}-#{i}", price: 100 }
      end
    end
  end

  def series_list(count)
    (1..count).map { |n| format('Serie %02d', n) }
  end

  describe 'landscape index fits on a single two-column page' do
    it 'lays out 22 series as one TOC page' do
      presentation = described_class.new(items: items_for(series_list(22)), orientation: :landscape)

      aggregate_failures do
        expect(presentation.toc_page_count).to eq(1)
        expect(presentation.toc_pages.size).to eq(1)
        expect(presentation.toc_pages.first.size).to eq(22)
      end
    end

    it 'keeps one TOC page exactly at the capacity boundary' do
      presentation = described_class.new(items: items_for(series_list(LANDSCAPE_TOC_CAPACITY)),
                                        orientation: :landscape)

      expect(presentation.toc_page_count).to eq(1)
    end

    it 'splits into two TOC pages once the series exceed one page capacity' do
      presentation = described_class.new(items: items_for(series_list(LANDSCAPE_TOC_CAPACITY + 1)),
                                        orientation: :landscape)

      aggregate_failures do
        expect(presentation.toc_page_count).to eq(2)
        expect(presentation.toc_pages.size).to eq(2)
      end
    end
  end

  describe 'landscape page numbers are derived from the one-page index' do
    it 'starts the products on page 3 (cover + one index page)' do
      presentation = described_class.new(items: items_for(series_list(22)), orientation: :landscape)

      aggregate_failures do
        expect(presentation.product_pages.first.page_number).to eq(3)
        expect(presentation.sections.first.first_page).to eq(3)
      end
    end

    it 'derives every section first_page and the total page count from the structure' do
      # Serie A: 8 productos (2 páginas de 6); Serie B: 4 productos (comparte la 2a).
      items = items_for(%w[A], per_series: 8) + items_for(%w[B], per_series: 4)
      presentation = described_class.new(items: items, orientation: :landscape)

      section_a, section_b = presentation.sections
      aggregate_failures do
        expect(section_a.first_page).to eq(3)
        expect(section_b.first_page).to eq(4)
        expect(presentation.product_pages.map(&:page_number)).to eq([3, 4])
        expect(presentation.total_pages)
          .to eq(1 + presentation.toc_page_count + presentation.product_pages.size)
      end
    end
  end

  describe 'portrait pagination is untouched' do
    it 'still spreads 22 series across two portrait index pages' do
      presentation = described_class.new(items: items_for(series_list(22)), orientation: :portrait)

      aggregate_failures do
        expect(described_class::TOC_ENTRIES_PER_PAGE.fetch(:portrait)).to eq(18)
        expect(presentation.toc_page_count).to eq(2)
        expect(presentation.product_pages.first.page_number).to eq(4)
      end
    end
  end
end
