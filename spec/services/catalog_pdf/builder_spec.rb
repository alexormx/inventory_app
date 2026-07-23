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
    it 'places every novelty first, ranked new > reappeared > restocked' do
      order = build_with(metadata, sort: 'name', prioritize_new: '1').send(:selection).map { |i| i[:name] }
      # Novedades primero por prioridad de evento, luego el resto por serie+nombre.
      expect(order).to eq(%w[A-new E-reapp C-restk B-plain D-plain])
    end

    it 'is a no-op when disabled' do
      order = build_with(metadata, sort: 'name', prioritize_new: '0').send(:selection).map { |i| i[:name] }
      expect(order).to eq(%w[B-plain C-restk A-new D-plain E-reapp])
    end
  end
end
