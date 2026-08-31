# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CatalogPdf::Builder do
  # Ordena la selección sin descargar imágenes: stubeamos la metadata para
  # probar solo la lógica de orden (series + secundario + novedades primero).
  def build_with(metadata, **opts)
    builder = described_class.new(source: 'local', **opts)
    allow(builder).to receive(:metadata).and_return(metadata)
    builder
  end

  def item(name:, series:, event: nil)
    { code: name, name: name, series: series, price: 0, event: event }
  end

  let(:metadata) do
    [
      item(name: 'B-plain',  series: 'Alpha'),
      item(name: 'A-new',    series: 'Beta',  event: 'new'),
      item(name: 'C-restk',  series: 'Alpha', event: 'restocked'),
      item(name: 'D-plain',  series: 'Beta'),
      item(name: 'E-reapp',  series: 'Beta',  event: 'reappeared')
    ]
  end

  describe 'default ordering (series then secondary)' do
    it 'ignores events and orders by series then name' do
      order = build_with(metadata, sort: 'name').send(:selection).map { |i| i[:name] }
      expect(order).to eq(%w[B-plain C-restk A-new D-plain E-reapp])
    end
  end

  describe 'prioritize_new' do
    # Antes subía CUALQUIER evento vigente. La opción significa ahora
    # "priorizar lanzamientos recientes": de vuelta y resurtido son eventos
    # comerciales distintos y conservan su lugar en el orden normal, sin perder
    # su badge.
    it 'sube sólo los estrenos y deja el resto en su orden normal' do
      order = build_with(metadata, sort: 'name', prioritize_new: '1').send(:selection).map { |i| i[:name] }
      expect(order).to eq(%w[A-new B-plain C-restk D-plain E-reapp])
    end

    it 'no adelanta un producto de vuelta' do
      order = build_with(metadata, sort: 'name', prioritize_new: '1').send(:selection).map { |i| i[:name] }
      expect(order.index('E-reapp')).to be > order.index('B-plain')
    end

    it 'no adelanta un producto resurtido' do
      order = build_with(metadata, sort: 'name', prioritize_new: '1').send(:selection).map { |i| i[:name] }
      expect(order.index('C-restk')).to be > order.index('A-new')
    end

    # Caso borde exigido: lanzado hace poco pero republicado DESPUÉS. Llega aquí
    # ya clasificado como :reappeared por Product#catalog_event, así que no debe
    # colarse al grupo de estrenos.
    it 'no mete al grupo de estrenos un lanzamiento reciente que fue republicado después' do
      relaunched = item(name: 'F-relaunched', series: 'Alpha', event: 'reappeared')
      order = build_with(metadata + [relaunched], sort: 'name', prioritize_new: '1')
              .send(:selection).map { |i| i[:name] }
      aggregate_failures do
        expect(order.first).to eq('A-new')
        expect(order.index('F-relaunched')).to be > order.index('A-new')
      end
    end

    it 'is a no-op when disabled' do
      order = build_with(metadata, sort: 'name', prioritize_new: '0').send(:selection).map { |i| i[:name] }
      expect(order).to eq(%w[B-plain C-restk A-new D-plain E-reapp])
    end
  end
end
