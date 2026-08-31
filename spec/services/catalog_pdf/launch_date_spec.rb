# frozen_string_literal: true

require 'rails_helper'

# La fecha de lanzamiento tiene que llegar igual venga de la base local o de la
# API de producción, porque el generador arranca por defecto contra la API.
RSpec.describe 'CatalogPdf: fecha de lanzamiento' do
  describe CatalogPdf::ProductSource do
    it 'expone first_published_at en ISO 8601' do
      launched = Time.zone.parse('2026-03-04 10:30:00')
      product = create(:product, skip_seed_inventory: true, status: 'active')
      product.update_columns(first_published_at: launched, created_at: 2.years.ago)

      fields = described_class.base_fields(product.reload)

      aggregate_failures do
        expect(fields[:launch_date]).to eq(launched.iso8601)
        expect(fields[:launch_date]).to be_a(String)
      end
    end

    it 'deja la fecha en nil cuando el producto nunca se publicó' do
      product = create(:product, skip_seed_inventory: true)
      product.update_columns(first_published_at: nil)

      expect(described_class.base_fields(product.reload)[:launch_date]).to be_nil
    end

    # created_at es cuándo se dio de alta el registro; no es el lanzamiento.
    it 'no usa created_at como fecha de lanzamiento' do
      product = create(:product, skip_seed_inventory: true, status: 'active')
      product.update_columns(first_published_at: nil, created_at: 5.days.ago)

      expect(described_class.base_fields(product.reload)[:launch_date]).to be_nil
    end
  end

  describe CatalogPdf::RemoteSource do
    it 'normaliza launch_date igual que la fuente local' do
      item = described_class.normalize('code' => 'A1', 'name' => 'X', 'series' => 'S',
                                       'price' => 10, 'launch_date' => '2026-03-04T10:30:00-06:00')

      expect(item[:launch_date]).to eq('2026-03-04T10:30:00-06:00')
    end

    it 'deja nil cuando la API no manda la fecha' do
      item = described_class.normalize('code' => 'A1', 'name' => 'X', 'series' => 'S', 'price' => 10)

      expect(item[:launch_date]).to be_nil
    end
  end

  describe CatalogPdfHelper do
    include described_class

    it 'formatea la fecha como DD/MM/YYYY' do
      expect(catalog_pdf_launch_date('2026-03-04T10:30:00-06:00')).to eq('04/03/2026')
    end

    it 'acepta un objeto de tiempo' do
      expect(catalog_pdf_launch_date(Time.zone.parse('2026-12-31 08:00'))).to eq('31/12/2026')
    end

    it 'devuelve nil ante valores ausentes o ilegibles' do
      aggregate_failures do
        expect(catalog_pdf_launch_date(nil)).to be_nil
        expect(catalog_pdf_launch_date('')).to be_nil
        expect(catalog_pdf_launch_date('no es una fecha')).to be_nil
      end
    end
  end
end
