# frozen_string_literal: true

module Collectibles
  # Identifica un coleccionable a partir de hasta 3 fotos (y las pistas del
  # admin) y busca fecha de lanzamiento, rareza y precios (México y mundial por
  # separado).
  #
  # Antes de la IA, Google Cloud Vision hace búsqueda inversa sobre la primera
  # foto (ReverseImageSearch, con tope mensual) y sus sugerencias se le pasan a
  # la IA como candidatos a confirmar. Luego una sola llamada a la Responses
  # API: fotos + web_search abierto + esquema estricto. Lo que regresa la IA se
  # valida aquí: un anuncio fuera de AiLookupSources se tira y el rango se
  # recalcula con lo que queda.
  # No sabe nada de HTTP ni de la pantalla; AiLookupJob guarda el resultado.
  class AiLookupService
    class Error < StandardError; end
    class RateLimitError < Error; end
    class NotConfiguredError < Error; end

    MODEL = 'gpt-4.1'
    REQUEST_TIMEOUT = 90
    IMAGE_MAX_EDGE = 1024
    MAX_LISTINGS = 5
    MAX_PHOTOS = AiLookup::MAX_PHOTOS
    MAX_CANDIDATES = 3
    YEN = /[¥￥円]|JPY/
    # USD, página de precios de OpenAI verificada el 2026-10-04 (gpt-4.1; en
    # modelos no razonadores los tokens del contenido buscado no se cobran).
    COST_INPUT_PER_M_USD = 2.00
    COST_OUTPUT_PER_M_USD = 8.00
    COST_PER_1K_SEARCHES_USD = 25.00

    INSTRUCTIONS = <<~PROMPT
      Eres experto en coleccionables (autos a escala, Tomica, Hot Wheels, Greenlight, figuras) para la tienda mexicana "Pasatiempos a Escala".
      1. Identifica la pieza usando TODAS las fotos: nombre comercial, marca, serie, código del fabricante, escala y año o edición.
         Las fotos suelen venir en este orden: 1) vista 3/4 elevada de la pieza, 2) la base con el texto del casting (marca, modelo, año, país), 3) la caja, blíster o etiqueta. Lee con cuidado el texto de la base y de la caja.
      2. Si hay pistas del admin, tómalas como ciertas salvo que la foto las contradiga claramente.
      3. Si hay resultados de búsqueda inversa de Google, son candidatos: confírmalos o descártalos; pueden estar mal.
      4. Antes de responder, confirma la identificación con al menos 2 búsquedas web en cualquier sitio (fabricante, hobbyDB, wikis, tiendas). Haz como máximo 6 búsquedas en total.
      5. Busca su fecha de lanzamiento, qué tan rara es y precios reales.
      6. prices_mx: sólo anuncios de mercadolibre.com.mx y amazon.com.mx, precio en MXN.
         prices_world: sólo ebay.com, amazon.com, amazon.co.jp, hobbydb.com, plazajapan.com y hlj.com; convierte cada precio a USD en `price` y pon el precio tal como aparece (con su moneda) en `price_original`.
      7. Cada anuncio debe ser de la misma pieza y llevar su URL real. Marca `sold` = true sólo si es una venta concluida.
      8. Si no encuentras datos confiables para un mercado, ese mercado es null. Nunca inventes precios, fechas ni URLs.
      9. launch_date.value en formato YYYY-MM-DD, YYYY-MM o YYYY según lo que sepas con certeza; null si no lo sabes. source_url: la página donde lo confirmaste.
      10. rarity.level: comun, poco_comun, rara o muy_rara, con razones concretas (tiraje, edición limitada, descontinuado, variante).
      11. suggested.description_es: 1 o 2 párrafos breves y factuales en español de México; sin precios, sin códigos de tiendas, sin SKUs, sin URLs.
      12. confidence de 0.0 a 1.0 sobre la identificación; sé honesto: si dudas entre piezas parecidas, baja de 0.7.
      13. candidates: hasta 3 piezas posibles, la más probable primero (igual a identification), cada una con una razón breve y su confianza. Anota dudas en warnings.
    PROMPT

    USER_TEXT = 'Identifica este coleccionable y dame fecha de lanzamiento, rareza y precios en México y en el mundo.'

    Result = Struct.new(:data, :tokens_input, :tokens_output, :web_search_calls, :cost_cents, keyword_init: true)

    def initialize(lookup, client: nil)
      @lookup = lookup
      @client = client
    end

    def call
      raise NotConfiguredError, 'OpenAI no está configurado' if OpenAI.configuration.access_token.blank?

      photos = processed_photos
      reverse_image = reverse_image_search(photos.first)
      response = request(user_content(photos, reverse_image))
      usage = response['usage'] || {}
      searches = Array(response['output']).count { |item| item['type'] == 'web_search_call' }

      Result.new(
        data: sanitize(parse(response)).merge('reverse_image' => reverse_image),
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

    def request(content)
      client.responses.create(parameters: {
                                model: MODEL,
                                instructions: INSTRUCTIONS,
                                input: [{ role: 'user', content: content }],
                                # Búsqueda abierta para identificar; los precios se
                                # filtran después contra AiLookupSources.
                                tools: [{ type: 'web_search' }],
                                text: { format: { type: 'json_schema', name: 'collectible_lookup',
                                                  schema: AiLookupSchema::SCHEMA, strict: true } }
                              })
    end

    def user_content(photos, reverse_image)
      text = [USER_TEXT]
      text << "Pistas del admin (tómalas como ciertas salvo que la foto las contradiga claramente): #{@lookup.hints}" if @lookup.hints.present?
      text << "Búsqueda inversa de Google (candidatos a confirmar, pueden estar mal): #{reverse_image.to_json}" if reverse_image

      [{ type: 'input_text', text: text.join("\n\n") }] +
        photos.map { |jpeg| { type: 'input_image', image_url: "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}", detail: 'high' } }
    end

    # Google cobra por llamada, no por resultado útil: el uso (y lo que dio) se
    # guarda en cuanto se llamó, antes de OpenAI. Así el tope mensual no se
    # queda corto y un reintento por 429 reusa la respuesta en vez de pagar otra.
    def reverse_image_search(jpeg)
      return @lookup.result&.dig('reverse_image') if @lookup.vision_used?
      return nil if AiLookup.vision_monthly_cap_reached?

      search = ReverseImageSearch.new(jpeg)
      result = search.call
      @lookup.update_columns(vision_used: true, result: { 'reverse_image' => result }) if search.called?
      result
    end

    # La foto de un teléfono pesa varios MB y trae GPS en el EXIF: se reduce y se
    # limpia antes de salir del servidor, y nunca se carga el original como base64.
    # 1024 px basta: OpenAI en `high` deja el lado corto en 768 px de todos modos.
    def processed_photos
      @lookup.ordered_photos.first(MAX_PHOTOS).map { |photo| processed_jpeg(photo) }
    end

    def processed_jpeg(photo)
      photo.blob.open do |file|
        # `.strip` se pasa tal cual a ImageMagick como -strip (quita EXIF/GPS y comentarios).
        resized = ImageProcessing::MiniMagick.source(file.path)
                                             .resize_to_limit(IMAGE_MAX_EDGE, IMAGE_MAX_EDGE)
                                             .strip
                                             .convert('jpg')
                                             .saver(quality: 85)
                                             .call
        begin
          File.binread(resized.path)
        ensure
          resized.close!
        end
      end
    rescue MiniMagick::Error, ImageProcessing::Error => e
      raise Error, "La foto #{photo.filename} no es una imagen válida: #{e.message.lines.first.to_s.strip}"
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

      data['candidates'] = Array(data['candidates']).select { |c| c.is_a?(Hash) }.first(MAX_CANDIDATES)

      # La fecha se confirma en el sitio del fabricante o en wikis, no sólo en
      # tiendas: se acepta cualquier http(s); lo demás (javascript:, etc.) no.
      launch = data['launch_date']
      launch['source_url'] = nil if launch.is_a?(Hash) && AiLookupSources.https_host(launch['source_url']).blank?
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
