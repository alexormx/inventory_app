# frozen_string_literal: true

module Collectibles
  # Convierte en el servidor el precio de un anuncio (`price_original`, tal como
  # lo publica la tienda) a la moneda del mercado, con los tipos de cambio que
  # el admin guarda en Guías de búsqueda (variables TIPO_CAMBIO_*, en pesos por
  # unidad). Así el rango no depende del tipo de cambio que se le ocurra a la IA.
  # Sin tipo de cambio, o si no se reconoce la moneda, se queda el de la IA.
  module PriceConversion
    CURRENCIES = %w[USD JPY EUR GBP].freeze
    VARIABLE_PREFIX = 'TIPO_CAMBIO_'
    MARKET_CURRENCY = { mx: 'MXN', world: 'USD' }.freeze

    module_function

    def variable_name(currency)
      "#{VARIABLE_PREFIX}#{currency}"
    end

    # Pesos por 1 unidad de cada moneda (sólo las que tienen un valor válido).
    def rates
      CURRENCIES.each_with_object({ 'MXN' => 1.0 }) do |currency, rates|
        rate = SystemVariable.get(variable_name(currency)).to_s.tr(',', '.').to_f
        rates[currency] = rate if rate.positive?
      end
    end

    # [moneda, monto] de un precio como «¥1,320», «US $12.50», «$349 MXN» o
    # «12,50 €»; la moneda es nil si no se reconoce (C $, AU $…). Un «$» solo es
    # la moneda del mercado: en Mercado Libre son pesos y en eBay dólares.
    def parse(text, market)
      text = text.to_s
      [currency_of(text, market), amount_of(text)]
    end

    # El precio del anuncio en la moneda del mercado y cómo se obtuvo:
    # 'original' (ya venía en esa moneda), 'servidor' (convertido aquí) o 'ia'.
    def convert(listing, market, rates)
      target = MARKET_CURRENCY.fetch(market)
      currency, amount = parse(listing['price_original'], market)
      return [listing['price'], 'ia', currency] unless currency && amount&.positive?
      return [amount, 'original', currency] if currency == target
      return [listing['price'], 'ia', currency] unless rates[currency] && rates[target]

      [(amount * rates[currency] / rates[target]).round(2), 'servidor', currency]
    end

    def currency_of(text, market)
      case text
      when /[¥￥円]|JPY/i then 'JPY'
      when /€|EUR/i then 'EUR'
      when /£|GBP/i then 'GBP'
      when /MXN|MX\s?\$/i then 'MXN'
      when /USD|US\s?\$|U\$S/i then 'USD'
      when /\b(?:C|CA|AU|A|NZ|HK|S)\s?\$/ then nil
      when /\$/ then MARKET_CURRENCY.fetch(market)
      end
    end

    # «1,320» y «1.320» son miles; «8.90» y «8,90» llevan centavos.
    def amount_of(text)
      number = text[/\d[\d.,]*/]
      return nil unless number

      separators = number.scan(/[.,]/)
      if separators.uniq.size > 1
        decimal = number.rindex(/[.,]/)
        whole = number[0...decimal].delete('.,')
        "#{whole}.#{number[(decimal + 1)..]}".to_f
      elsif separators.any? && number.split(/[.,]/).last.size == 3
        number.delete('.,').to_f
      else
        number.tr(',', '.').to_f
      end
    end
  end
end
