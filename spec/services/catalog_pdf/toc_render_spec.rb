# frozen_string_literal: true

require 'rails_helper'

# Regresión del HTML del índice: una sola página apaisada con todas las series,
# sin la coletilla "Página X de Y" cuando el índice ocupa una única página, y
# con los números de destino derivados de la estructura real.
RSpec.describe 'CatalogPdf: render del índice' do
  def render_catalog(series_count:, orientation: :landscape)
    items = (1..series_count).map do |n|
      { code: "S#{n}", name: "Producto #{n}", brand: 'Tomica',
        series: format('Serie %02d', n), scale: nil, price: 100,
        event: nil, event_label: nil, launch_date: nil,
        product_url: 'https://pasatiempos.com.mx/products/p', unique_piece: false }
    end
    presentation = CatalogPdf::Presentation.new(items: items, orientation: orientation)
    wa = '5215555555555'
    wa_url = CatalogPdf::Links.whatsapp_url(number: wa)
    ApplicationController.render(
      template: 'catalog_pdf/show', layout: false,
      locals: { title: 'Catálogo', whatsapp_number: wa, items: items, logo: nil,
                usd_rate: nil, orientation: orientation, include_launch_date: false,
                presentation: presentation, cover_whatsapp_url: wa_url,
                whatsapp_number_raw: wa, qr_code: CatalogPdf::QrCode.data_uri(wa_url) }
    )
  end

  def toc_intros(html)
    Nokogiri::HTML(html).css('section.toc-page .toc-intro').map { |n| n.text.gsub(/\s+/, ' ').strip }
  end

  it 'renders exactly one landscape TOC page for 22 series' do
    html = render_catalog(series_count: 22)

    expect(Nokogiri::HTML(html).css('section.toc-page').size).to eq(1)
  end

  it 'lists all 22 series on that single landscape TOC page' do
    html = render_catalog(series_count: 22)

    expect(Nokogiri::HTML(html).css('section.toc-page .toc-entry').size).to eq(22)
  end

  it 'omits the "Página X de Y" sentence when the index is a single page' do
    html = render_catalog(series_count: 5)

    expect(toc_intros(html).first).not_to match(/Página\s+\d+\s+de\s+\d+/)
  end

  it 'still shows "Página X de Y" when the index legitimately spans two pages' do
    html = render_catalog(series_count: CatalogPdf::Presentation::TOC_ENTRIES_PER_PAGE.fetch(:landscape) + 1)

    intros = toc_intros(html)
    aggregate_failures do
      expect(intros.size).to eq(2)
      expect(intros.first).to match(/Página\s+1\s+de\s+2/)
      expect(intros.last).to match(/Página\s+2\s+de\s+2/)
    end
  end

  it 'points every index destination at page 3 or later, first section at page 3' do
    html = render_catalog(series_count: 22)

    pages = Nokogiri::HTML(html).css('section.toc-page .toc-entry .page').map { |n| n.text.to_i }
    aggregate_failures do
      expect(pages.size).to eq(22)
      expect(pages).to all(be >= 3)
      expect(pages.first).to eq(3)
    end
  end

  it 'leaves the portrait index untouched (two pages, sentence shown) for 22 series' do
    html = render_catalog(series_count: 22, orientation: :portrait)

    intros = toc_intros(html)
    aggregate_failures do
      expect(Nokogiri::HTML(html).css('section.toc-page').size).to eq(2)
      expect(intros.first).to match(/Página\s+1\s+de\s+2/)
    end
  end
end
