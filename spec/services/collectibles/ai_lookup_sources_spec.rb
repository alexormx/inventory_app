# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookupSources do
  describe '.allowed?' do
    it 'acepta subdominios del mercado correcto' do
      expect(described_class.allowed?('https://articulo.mercadolibre.com.mx/MLM-1', :mx)).to be(true)
      expect(described_class.allowed?('https://www.ebay.com/itm/1', :world)).to be(true)
    end

    it 'no confunde amazon.com.mx con amazon.com' do
      expect(described_class.allowed?('https://www.amazon.com.mx/dp/X', :world)).to be(false)
      expect(described_class.allowed?('https://www.amazon.com/dp/X', :mx)).to be(false)
    end

    it 'rechaza dominios fuera de la lista, imitaciones y esquemas raros' do
      expect(described_class.allowed?('https://ebay.com.scam.example/itm/1', :world)).to be(false)
      expect(described_class.allowed?('https://notebay.com/itm/1', :world)).to be(false)
      expect(described_class.allowed?('javascript:alert(1)//ebay.com', :world)).to be(false)
      expect(described_class.allowed?('not a url', :world)).to be(false)
      expect(described_class.allowed?(nil, :mx)).to be(false)
    end
  end

  it '.allowed_anywhere? acepta cualquiera de los dos mercados' do
    expect(described_class.allowed_anywhere?('https://hlj.com/product/x')).to be(true)
    expect(described_class.allowed_anywhere?('https://example.com')).to be(false)
  end
end
