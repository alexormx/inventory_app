# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CatalogPdf: navegación y pedidos' do
  def item(index, series: 'Tomica Premium', name: nil)
    {
      code: "PX#{index}", name: name || "Producto #{index}", brand: 'Takara Tomy',
      series: series, scale: '1/64', price: 250, event: nil, event_label: nil,
      launch_date: nil, unique_piece: false, image: CatalogPdf::SampleData.placeholder,
      product_url: "https://pasatiempos.com.mx/products/producto-#{index}"
    }
  end

  describe CatalogPdf::Presentation do
    it 'calcula secciones, páginas físicas y encabezados mixtos desde los productos incluidos' do
      items = Array.new(4) { |index| item(index, series: 'Serie A') } +
              Array.new(4) { |index| item(index + 4, series: 'Serie B') }
      presentation = described_class.new(items: items, orientation: :portrait)

      aggregate_failures do
        expect(presentation.sections.map { |section| [section.name, section.product_count, section.first_page] })
          .to eq([['Serie A', 4, 3], ['Serie B', 4, 3]])
        expect(presentation.product_pages.first.section_names).to eq(['Serie A', 'Serie B'])
        expect(presentation.product_pages.last.unused_slots).to eq(4)
        expect(presentation.total_pages).to eq(4)
      end
    end

    it 'pagina índices largos según la orientación sin cálculo circular' do
      portrait = described_class.new(
        items: Array.new(19) { |index| item(index, series: "Serie #{index}") }, orientation: :portrait
      )
      landscape = described_class.new(
        items: Array.new(15) { |index| item(index, series: "Serie #{index}") }, orientation: :landscape
      )

      aggregate_failures do
        expect(portrait.toc_pages.map(&:size)).to eq([18, 1])
        expect(portrait.sections.first.first_page).to eq(4)
        expect(landscape.toc_pages.map(&:size)).to eq([14, 1])
        expect(landscape.sections.first.first_page).to eq(4)
      end
    end

    it 'no reserva espacio de CTA cuando la página final está llena' do
      presentation = described_class.new(items: Array.new(6) { |index| item(index) }, orientation: :portrait)

      expect(presentation.product_pages.last.unused_slots).to be_zero
    end
  end

  describe CatalogPdf::Links do
    it 'codifica el mensaje y normaliza el teléfono de WhatsApp' do
      url = described_class.product_whatsapp_url(
        number: '+52 33 8526 2707', code: 'AD21', name: 'Subaru WRX S4 — Edición Especial'
      )
      uri = URI(url)

      aggregate_failures do
        expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq('https://wa.me/523385262707')
        expect(URI.decode_www_form(uri.query).to_h.fetch('text'))
          .to eq('Hola, me interesa el producto AD21 — Subaru WRX S4 — Edición Especial.')
      end
    end
  end

  describe CatalogPdf::QrCode do
    it 'genera un SVG vectorial embebido con zona blanca de seguridad' do
      data_uri = described_class.data_uri('https://wa.me/523385262707?text=Pedido')
      svg = Base64.strict_decode64(data_uri.delete_prefix('data:image/svg+xml;base64,'))

      aggregate_failures do
        expect(data_uri).to start_with('data:image/svg+xml;base64,')
        expect(svg).to include('<svg', '#128C7E', 'fill="#ffffff"')
      end
    end
  end

  describe CatalogPdf::Generator do
    let(:long_name) do
      'Tomica Premium Release Commemorative First Edition Special Edition Anniversary Limited Color'
    end

    it 'renderiza en vertical con título completo, índice, links y CTA parcial' do
      html = described_class.new(
        title: 'Catálogo', whatsapp_number: '+52 33 8526 2707',
        items: [item(1, name: long_name)], orientation: :portrait
      ).html

      aggregate_failures do
        expect(html).to include('class="portrait"', long_name, 'name--long')
        expect(html).to include('ÍNDICE', 'href="#catalog-section-1-tomica-premium"')
        expect(html).to include('1 coleccionable disponible', 'cta-card')
        expect(html).to include('Disponibilidad y precios vigentes al momento de generación del catálogo.')
        expect(html.scan('https://pasatiempos.com.mx/products/producto-1').size).to eq(2)
        expect(html).to include('me+interesa+el+producto+PX1')
        expect(html).not_to include('…', '...')
      end
    end

    it 'renderiza en horizontal y omite el CTA cuando la última página está llena' do
      html = described_class.new(
        title: 'Catálogo', whatsapp_number: '+52 33 8526 2707',
        items: Array.new(6) { |index| item(index) }, orientation: :landscape
      ).html

      aggregate_failures do
        expect(html).to include('class="landscape"', 'Tomica Premium')
        expect(html).not_to include('<div class="card cta-card">')
      end
    end

    it 'entrega al QR de portada la URL canónica exacta' do
      expected = CatalogPdf::Links.whatsapp_url(number: '+52 33 8526 2707')
      expect(CatalogPdf::QrCode).to receive(:data_uri).with(expected).and_return('data:image/svg+xml;base64,PHN2Zy8+')

      described_class.new(
        title: 'Catálogo', whatsapp_number: '+52 33 8526 2707', items: [item(1)]
      ).html
    end
  end

  describe CatalogPdf::ImageEncoder do
    it 'crea una copia JPEG acotada para el PDF' do
      require 'vips'
      original = Vips::Image.black(900, 600).jpegsave_buffer(Q: 90)
      encoded = described_class.data_uri(original)
      image = Vips::Image.new_from_buffer(Base64.strict_decode64(encoded.split(',', 2).last), '')

      aggregate_failures do
        expect(encoded).to start_with('data:image/jpeg;base64,')
        expect([image.width, image.height].max).to eq(described_class::MAX_IMAGE_PX)
        expect(image.has_alpha?).to be(false)
      end
    end
  end
end
