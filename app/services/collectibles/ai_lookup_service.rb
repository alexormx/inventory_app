# frozen_string_literal: true

module Collectibles
  # Identifica un coleccionable a partir de su foto y busca en sitios confiables
  # fecha de lanzamiento, rareza y precios (México y mundial por separado).
  #
  # Una sola llamada a la Responses API: imagen + web_search restringido a
  # AiLookupSources + esquema estricto. Lo que regresa la IA se valida aquí: un
  # enlace fuera de la lista se tira y el rango se recalcula con lo que queda.
  # No sabe nada de HTTP ni de la pantalla; AiLookupJob guarda el resultado.
  class AiLookupService
    class Error < StandardError; end
    class RateLimitError < Error; end
    class NotConfiguredError < Error; end

    MODEL = 'gpt-4.1'
    REQUEST_TIMEOUT = 90
    IMAGE_MAX_EDGE = 1024
    MAX_LISTINGS = 5
    YEN = /[¥￥円]|JPY/
    # USD, página de precios de OpenAI verificada el 2026-10-04 (gpt-4.1; en
    # modelos no razonadores los tokens del contenido buscado no se cobran).
    COST_INPUT_PER_M_USD = 2.00
    COST_OUTPUT_PER_M_USD = 8.00
    COST_PER_1K_SEARCHES_USD = 25.00

    INSTRUCTIONS = <<~PROMPT
      Eres experto en coleccionables (autos a escala, Tomica, Hot Wheels, figuras) para la tienda mexicana "Pasatiempos a Escala".
      1. Identifica la pieza de la foto: nombre comercial, marca, serie, código del fabricante, escala y año o edición.
      2. Busca en la web (sólo en los sitios permitidos) su fecha de lanzamiento, qué tan rara es y precios reales.
      3. prices_mx: sólo anuncios de mercadolibre.com.mx y amazon.com.mx, precio en MXN.
         prices_world: sólo ebay.com, amazon.com, amazon.co.jp, hobbydb.com, plazajapan.com y hlj.com; convierte cada precio a USD en `price` y pon el precio tal como aparece (con su moneda) en `price_original`.
      4. Cada anuncio debe ser de la misma pieza y llevar su URL real. Marca `sold` = true sólo si es una venta concluida.
      5. Si no encuentras datos confiables para un mercado, ese mercado es null. Nunca inventes precios, fechas ni URLs.
      6. launch_date.value en formato YYYY-MM-DD, YYYY-MM o YYYY según lo que sepas con certeza; null si no lo sabes.
      7. rarity.level: comun, poco_comun, rara o muy_rara, con razones concretas (tiraje, edición limitada, descontinuado, variante).
      8. suggested.description_es: 1 o 2 párrafos breves y factuales en español de México; sin precios, sin códigos de tiendas, sin SKUs, sin URLs.
      9. confidence de 0.0 a 1.0 sobre la identificación. Anota dudas en warnings.
      10. Haz como máximo 6 búsquedas.
    PROMPT

    USER_TEXT = 'Identifica este coleccionable y dame fecha de lanzamiento, rareza y precios en México y en el mundo.'

    Result = Struct.new(:data, :tokens_input, :tokens_output, :web_search_calls, :cost_cents, keyword_init: true)

    def initialize(lookup, client: nil)
      @lookup = lookup
      @client = client
    end

    def call
      raise NotConfiguredError, 'OpenAI no está configurado' if OpenAI.configuration.access_token.blank?

      response = request(image_data_url)
      usage = response['usage'] || {}
      searches = Array(response['output']).count { |item| item['type'] == 'web_search_call' }

      Result.new(
        data: sanitize(parse(response)),
        tokens_input: usage['input_tokens'].to_i,
        tokens_output: usage['output_tokens'].to_i,
        web_search_calls: searches,
        cost_cents: cost_cents(usage['input_tokens'].to_i, usage['output_tokens'].to_i, searches)
      )
    rescue Faraday::TooManyRequestsError => e
      raise RateLimitError, "OpenAI está saturado (429): #{e.message}"
    end

    private

    def client
      @client ||= OpenAI::Client.new(request_timeout: REQUEST_TIMEOUT)
    end

    def request(image_url)
      client.responses.create(parameters: {
                                model: MODEL,
                                instructions: INSTRUCTIONS,
                                input: [{
                                  role: 'user',
                                  content: [
                                    { type: 'input_text', text: USER_TEXT },
                                    { type: 'input_image', image_url: image_url, detail: 'high' }
                                  ]
                                }],
                                tools: [{ type: 'web_search', filters: { allowed_domains: AiLookupSources::ALL } }],
                                text: { format: { type: 'json_schema', name: 'collectible_lookup',
                                                  schema: AiLookupSchema::SCHEMA, strict: true } }
                              })
    end

    # La foto de un teléfono pesa varios MB y trae GPS en el EXIF: se reduce y se
    # limpia antes de salir del servidor, y nunca se carga el original como base64.
    def image_data_url
      @lookup.ordered_photos.first.blob.open do |file|
        # `.strip` se pasa tal cual a ImageMagick como -strip (quita EXIF/GPS y comentarios).
        resized = ImageProcessing::MiniMagick.source(file.path)
                                             .resize_to_limit(IMAGE_MAX_EDGE, IMAGE_MAX_EDGE)
                                             .strip
                                             .convert('jpg')
                                             .saver(quality: 85)
                                             .call
        begin
          "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(resized.path))}"
        ensure
          resized.close!
        end
      end
    rescue MiniMagick::Error, ImageProcessing::Error => e
      raise Error, "La foto no es una imagen válida: #{e.message.lines.first.to_s.strip}"
    end

    def parse(response)
      message = Array(response['output']).find { |item| item['type'] == 'message' }
      content = Array(message&.dig('content'))
      refusal = content.find { |c| c['type'] == 'refusal' }
      raise Error, "OpenAI rechazó la solicitud: #{refusal['refusal']}" if refusal

      text = content.find { |c| c['type'] == 'output_text' }&.dig('text')
      raise Error, 'Respuesta vacía de OpenAI' if text.blank?

      data = JSON.parse(text)
      raise Error, 'Respuesta inválida de OpenAI: falta identification' unless data.is_a?(Hash) && data['identification'].is_a?(Hash)

      data
    rescue JSON::ParserError => e
      Rails.logger.warn("[AiLookup] JSON inválido lookup=#{@lookup.id}: #{text.to_s.truncate(2000)}")
      raise Error, "Respuesta inválida de OpenAI: #{e.message}"
    end

    def sanitize(data)
      data = data.deep_dup
      data['warnings'] = Array(data['warnings'])
      drop_unconverted_yen(data)
      data['prices_mx'] = sanitize_market(data['prices_mx'], :mx, 'MXN')
      data['prices_world'] = sanitize_market(data['prices_world'], :world, 'USD')

      launch = data['launch_date']
      if launch.is_a?(Hash) && launch['source_url'].present? && !AiLookupSources.allowed_anywhere?(launch['source_url'])
        launch['source_url'] = nil
        data['warnings'] << 'La fuente de la fecha de lanzamiento no es un sitio confiable; verifícala.'
      end
      data
    end

    # HLJ y Amazon JP publican en yenes; si la IA copia ¥1,320 como `price: 1320`
    # el rango diría USD $1,320. Un precio ya convertido es ~1/150 del monto en
    # yenes, así que cualquiera que llegue a la mitad del original no se convirtió.
    def drop_unconverted_yen(data)
      market = data['prices_world']
      return unless market.is_a?(Hash) && market['listings'].is_a?(Array)

      kept = market['listings'].reject { |listing| unconverted_yen?(listing) }
      return if kept.size == market['listings'].size

      market['listings'] = kept
      data['warnings'] << 'Se descartaron precios en yenes que no venían convertidos a USD.'
    end

    def unconverted_yen?(listing)
      return false unless listing.is_a?(Hash) && listing['price'].is_a?(Numeric) && listing['price_original'].to_s.match?(YEN)

      amount = listing['price_original'].to_s.delete(',')[/\d+(?:\.\d+)?/].to_f
      amount.positive? && listing['price'] >= amount * 0.5
    end

    def sanitize_market(market, key, currency)
      return nil unless market.is_a?(Hash)

      listings = Array(market['listings']).select do |listing|
        listing.is_a?(Hash) && AiLookupSources.allowed?(listing['url'], key) &&
          listing['price'].is_a?(Numeric) && listing['price'].positive?
      end.first(MAX_LISTINGS)
      return nil if listings.empty?

      prices = listings.pluck('price')
      { 'min' => prices.min, 'max' => prices.max, 'currency' => currency, 'listings' => listings }
    end

    def cost_cents(input_tokens, output_tokens, searches)
      usd = (input_tokens / 1_000_000.0 * COST_INPUT_PER_M_USD) +
            (output_tokens / 1_000_000.0 * COST_OUTPUT_PER_M_USD) +
            (searches / 1000.0 * COST_PER_1K_SEARCHES_USD)
      (usd * 100).ceil
    end
  end
end
