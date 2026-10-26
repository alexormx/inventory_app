# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::LookupSource do
  def source(attrs = {})
    described_class.new({ name: 'eBay', domain: 'ebay.com', purpose: 'prices_world' }.merge(attrs))
  end

  it 'deja sólo el dominio de una URL pegada y la categoría en minúsculas' do
    s = source(domain: ' https://www.eBay.com/itm/123?x=1 ', category: ' Autos a Escala ', notes: '  ')
    expect(s).to be_valid
    expect([s.domain, s.category, s.notes]).to eq(['ebay.com', 'autos a escala', nil])
  end

  it 'valida dominio, nombre y búsqueda a mano' do
    expect(source(domain: 'no es dominio')).not_to be_valid
    expect(source(name: '')).not_to be_valid
    expect(source(search_url: 'http://ebay.com/?q={q}')).not_to be_valid
    expect(source(search_url: 'https://ebay.com/sch')).not_to be_valid
    expect(source(search_url: 'https://ebay.com/sch?q={q}')).to be_valid
  end

  it 'no repite el mismo dominio en la misma guía y categoría' do
    source.save!
    expect(source).not_to be_valid
    expect(source(purpose: 'reference')).to be_valid
    expect(source(category: 'figuras')).to be_valid
  end

  describe 'sitios sugeridos' do
    it 'se usan mientras no haya ninguna guía guardada' do
      expect(described_class.configured?).to be(false)
      expect(described_class.price_domains(:mx)).to eq(%w[mercadolibre.com.mx amazon.com.mx])
      expect(described_class.price_domains(:world)).to include('ebay.com', 'hlj.com', 'mandarake.co.jp')
    end

    it 'son todos válidos y se guardan una sola vez' do
      described_class::DEFAULTS.each { |attrs| expect(described_class.new(attrs)).to be_valid, attrs[:name] }
      expect(described_class.install_defaults!).to be(true)
      expect(described_class.count).to eq(described_class::DEFAULTS.size)
      expect(described_class.install_defaults!).to be(false)
      expect(described_class.count).to eq(described_class::DEFAULTS.size)
    end

    it 'en cuanto hay guías guardadas, sólo cuentan las activas' do
      source(active: false).save!
      expect(described_class.price_domains(:world)).to eq([])
    end
  end

  describe '.search_links' do
    before do
      source(search_url: 'https://www.ebay.com/sch/i.html?_nkw={q}&LH_Sold=1', position: 0).save!
      source(name: 'Wiki', domain: 'hotwheels.fandom.com', purpose: 'reference', category: 'hot wheels',
             search_url: 'https://hotwheels.fandom.com/wiki/Special:Search?query={q}', position: 1).save!
      source(name: 'Sin búsqueda', domain: 'hlj.com', position: 2).save!
    end

    it 'arma la búsqueda con el nombre codificado; los de otra categoría no salen' do
      links = described_class.search_links('Skyline GT-R & R34', category: 'Autos a escala')
      expect(links).to eq([{ 'name' => 'eBay', 'purpose' => 'prices_world',
                             'url' => 'https://www.ebay.com/sch/i.html?_nkw=Skyline%20GT-R%20%26%20R34&LH_Sold=1' }])
    end

    it 'los de su categoría sí salen' do
      expect(described_class.search_links('Twin Mill', category: 'Hot Wheels').pluck('name')).to eq(%w[eBay Wiki])
    end

    it 'sin nombre no hay enlaces' do
      expect(described_class.search_links(nil)).to eq([])
    end
  end
end
