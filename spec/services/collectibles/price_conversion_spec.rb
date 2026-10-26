# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::PriceConversion do
  describe '.parse' do
    {
      '¥1,320' => ['JPY', 1320.0],
      '1.320円' => ['JPY', 1320.0],
      'US $12.50' => ['USD', 12.5],
      '$1,234.56' => ['USD', 1234.56],
      '12,50 €' => ['EUR', 12.5],
      '1.234,50 EUR' => ['EUR', 1234.5],
      '£8.99' => ['GBP', 8.99],
      '$349 MXN' => ['MXN', 349.0],
      'C $15.00' => [nil, 15.0],
      'precio a consultar' => [nil, nil]
    }.each do |text, expected|
      it "lee #{text.inspect} en el mercado mundial" do
        expect(described_class.parse(text, :world)).to eq(expected)
      end
    end

    it 'un $ solo es la moneda del mercado' do
      expect(described_class.parse('$349', :mx)).to eq(['MXN', 349.0])
      expect(described_class.parse('$12', :world)).to eq(['USD', 12.0])
    end
  end

  describe '.convert' do
    let(:rates) { { 'MXN' => 1.0, 'USD' => 20.0, 'JPY' => 0.13 } }

    it 'pasa de yenes a dólares y de dólares a pesos con los tipos del admin' do
      expect(described_class.convert({ 'price' => 9, 'price_original' => '¥2,000' }, :world, rates))
        .to eq([13.0, 'servidor', 'JPY'])
      expect(described_class.convert({ 'price' => 1, 'price_original' => 'US $10' }, :mx, rates))
        .to eq([200.0, 'servidor', 'USD'])
    end

    it 'sin tipo de cambio o con moneda desconocida se queda el precio de la IA' do
      expect(described_class.convert({ 'price' => 7.5, 'price_original' => '€7' }, :world, rates)).to eq([7.5, 'ia', 'EUR'])
      expect(described_class.convert({ 'price' => 11, 'price_original' => 'C $15' }, :world, rates)).to eq([11, 'ia', nil])
    end
  end

  it '.rates lee las variables válidas, con coma o punto' do
    SystemVariable.set('TIPO_CAMBIO_USD', '18,5')
    SystemVariable.set('TIPO_CAMBIO_JPY', 'no')
    expect(described_class.rates).to eq('MXN' => 1.0, 'USD' => 18.5)
  end
end
