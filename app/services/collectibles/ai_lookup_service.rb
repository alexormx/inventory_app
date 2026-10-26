# frozen_string_literal: true

module Collectibles
  # Identifica un coleccionable a partir de hasta 5 fotos (cada una con su tipo)
  # y las pistas del admin, y busca fecha de lanzamiento, rareza y precios
  # (México y mundial por separado).
  #
  # Antes de la IA, Google Cloud Vision hace búsqueda inversa sobre la vista
  # 3/4 (ReverseImageSearch, con tope mensual) y sus sugerencias se le pasan a
  # la IA como candidatos a confirmar. Luego una sola llamada a la Responses
  # API: fotos + web_search abierto + esquema estricto, con las guías de
  # búsqueda (LookupSource) en las instrucciones. Lo que regresa la IA se
  # valida aquí: un anuncio fuera de las guías de precios, o que la búsqueda
  # no visitó, se tira; el precio se convierte con los tipos de cambio del
  # admin y el rango se recalcula con lo que queda (vendidos y en venta aparte).
  # No sabe nada de HTTP ni de la pantalla; AiLookupJob guarda el resultado.
  class AiLookupService
    class Error < StandardError; end
    class RateLimitError < Error; end
    class NotConfiguredError < Error; end

    MODEL = 'gpt-4.1'
    REQUEST_TIMEOUT = 90
    IMAGE_MAX_EDGE = Images::AiReadyJpeg::MAX_EDGE
    MAX_LISTINGS = 5
    MAX_PHOTOS = AiLookup::MAX_PHOTOS
    MAX_CANDIDATES = 3
    YEN = /[¥￥円]|JPY/
    UNCONFIRMED_WARNING = 'OpenAI no devolvió las páginas que visitó: los anuncios no se pudieron confirmar; ' \
                          'ábrelos antes de usarlos.'
    # USD, página de precios de OpenAI verificada el 2026-10-04 (gpt-4.1; en
    # modelos no razonadores los tokens del contenido buscado no se cobran).
    COST_INPUT_PER_M_USD = 2.00
    COST_OUTPUT_PER_M_USD = 8.00
    COST_PER_1K_SEARCHES_USD = 25.00

    INSTRUCTIONS = <<~PROMPT
      Eres experto en coleccionables (autos a escala, Tomica, Hot Wheels, Greenlight, figuras) para la tienda mexicana "Pasatiempos a Escala".
      1. Identifica la pieza usando TODAS las fotos: nombre comercial, marca, serie, código del fabricante, escala y año o edición.
         Cada foto viene precedida de su tipo (vista 3/4, base, lateral, superior, empaque). En la foto de la base lee con cuidado el texto del casting (marca, modelo, año, país); en la del empaque, el texto de la caja o etiqueta.
      2. Si hay pistas del admin, tómalas como ciertas salvo que la foto las contradiga claramente.
      3. Si hay resultados de búsqueda inversa de Google, son candidatos: confírmalos o descártalos; pueden estar mal.
      4. Antes de responder, confirma la identificación con al menos 2 búsquedas web. Empieza por las guías para identificar de abajo; si no alcanzan, usa cualquier otro sitio (fabricante, wikis, tiendas). Haz como máximo 6 búsquedas en total.
      5. Busca su fecha de lanzamiento, qué tan rara es y precios reales.
      6. prices_mx: sólo anuncios de los sitios de «Precios en México» de abajo, precio en MXN.
         prices_world: sólo anuncios de los sitios de «Precios en el mundo» de abajo; convierte cada precio a USD en `price`.
         En los dos pon el precio tal como aparece en la página (con su moneda) en `price_original`.
      7. Cada anuncio debe ser de la misma pieza y llevar la URL exacta de la página que visitaste. Marca `sold` = true sólo si es una venta concluida. `date`: fecha del anuncio o de la venta (YYYY-MM-DD) si aparece; si no, null.
      8. Si no encuentras datos confiables para un mercado, ese mercado es null. Nunca inventes precios, fechas ni URLs.
      9. launch_date.value en formato YYYY-MM-DD, YYYY-MM o YYYY según lo que sepas con certeza; null si no lo sabes. source_url: la página donde lo confirmaste.
      10. rarity.level: comun, poco_comun, rara o muy_rara, con razones concretas (tiraje, edición limitada, descontinuado, variante).
      11. suggested.description_es: 1 o 2 párrafos breves y factuales en español de México; sin precios, sin códigos de tiendas, sin SKUs, sin URLs.
      12. confidence de 0.0 a 1.0 sobre la identificación; sé honesto: si dudas entre piezas parecidas, baja de 0.7.
      13. candidates: hasta 3 piezas posibles, la más probable primero (igual a identification), cada una con una razón breve y su confianza. Anota dudas en warnings.
    PROMPT

    USER_TEXT = 'Identifica este coleccionable y dame fecha de lanzamiento, rareza y precios en México y en el mundo.'

    Result = Struct.new(:data, :tokens_input, :tokens_output, :web_search_calls, :cost_cents, keyword_init: true)

    GUIDE_TITLES = {
      'reference' => 'Guías para identificar, fecha y rareza (puedes usar otros sitios)',
      'prices_mx' => 'Precios en México (sólo estos sitios)',
      'prices_world' => 'Precios en el mundo (sólo estos sitios)'
    }.freeze

    # Las instrucciones fijas más las guías de búsqueda del admin.
    def self.instructions(sources = LookupSource.in_use)
      guides = GUIDE_TITLES.map do |purpose, title|
        lines = sources.select { |source| source.purpose == purpose }.map(&:prompt_line)
        lines = ["- (ninguno: deja #{purpose} en null)"] if lines.empty? && purpose != 'reference'
        lines.empty? ? nil : "#{title}:\n#{lines.join("\n")}"
      end
      [INSTRUCTIONS, *guides.compact].join("\n")
    end

    def initialize(lookup, client: nil)
      @lookup = lookup
      @client = client
    end

    def call
      raise NotConfiguredError, 'OpenAI no está configurado' if OpenAI.configuration.access_token.blank?

      photos = processed_photos
      reverse_image = reverse_image_search(vision_jpeg(photos))
      response = request(user_content(photos, reverse_image))
      usage = response['usage'] || {}
      searches = Array(response['output']).count { |item| item['type'] == 'web_search_call' }

      Result.new(
        data: sanitize(parse(response), consulted_pages(response)).merge('reverse_image' => reverse_image),
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
                                instructions: self.class.instructions,
                                input: [{ role: 'user', content: content }],
                                # Búsqueda abierta para identificar; los precios se
                                # filtran después contra AiLookupSources.
                                tools: [{ type: 'web_search' }],
                                # Las páginas que la búsqueda visitó de verdad: un
                                # anuncio que no esté ahí es un enlace inventado.
                                include: ['web_search_call.action.sources'],
                                text: { format: { type: 'json_schema', name: 'collectible_lookup',
                                                  schema: AiLookupSchema::SCHEMA, strict: true } }
                              })
    end

    def user_content(photos, reverse_image)
      text = [USER_TEXT]
      text << "Pistas del admin (tómalas como ciertas salvo que la foto las contradiga claramente): #{@lookup.hints}" if @lookup.hints.present?
      text << "Búsqueda inversa de Google (candidatos a confirmar, pueden estar mal): #{reverse_image.to_json}" if reverse_image

      [{ type: 'input_text', text: text.join("\n\n") }] +
        photos.each_with_index.flat_map do |(jpeg, role), index|
          [{ type: 'input_text', text: photo_label(index, role) },
           { type: 'input_image', image_url: "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}", detail: 'high' }]
        end
    end

    def photo_label(index, role)
      label = AiLookup::PHOTO_ROLES[role]
      label ? "Foto #{index + 1}: #{label}" : "Foto #{index + 1} (tipo no indicado)"
    end

    # Google reconoce mejor la vista 3/4; búsquedas sin tipos usan la primera foto.
    def vision_jpeg(photos)
      (photos.find { |_jpeg, role| role == 'three_quarter' } || photos.first).first
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
      @lookup.labeled_photos.first(MAX_PHOTOS).map { |photo, role| [processed_jpeg(photo), role] }
    end

    def processed_jpeg(photo)
      Images::AiReadyJpeg.call(photo)
    rescue Images::AiReadyJpeg::InvalidImage => e
      raise Error, "La foto #{photo.filename} no es una imagen válida: #{e.message}"
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

    # Las páginas que la búsqueda consultó (fuentes de cada búsqueda y citas del
    # mensaje), como AiLookupSources.page_key.
    def consulted_pages(response)
      urls = Array(response['output']).flat_map do |item|
        case item['type']
        when 'web_search_call'
          sources = item['action'].is_a?(Hash) ? Array(item['action']['sources']) : []
          sources.map { |source| source.is_a?(Hash) ? source['url'] : source }
        when 'message'
          Array(item['content']).flat_map { |c| Array(c['annotations']) }
                                .select { |a| a.is_a?(Hash) && a['type'] == 'url_citation' }
                                .pluck('url')
        else []
        end
      end
      urls.filter_map { |url| AiLookupSources.page_key(url) }.to_set
    end

    def sanitize(data, consulted)
      data = data.deep_dup
      data['warnings'] = Array(data['warnings'])
      checks = Hash.new(0)
      rates = PriceConversion.rates
      data['prices_mx'] = sanitize_market(data['prices_mx'], :mx, consulted, rates, checks)
      data['prices_world'] = sanitize_market(data['prices_world'], :world, consulted, rates, checks)
      data['warnings'].concat(check_warnings(checks, consulted))

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
    # Sólo aplica cuando el precio es el de la IA (sin tipo de cambio del yen).
    def unconverted_yen?(listing)
      return false unless listing['price'].is_a?(Numeric) && listing['price_original'].to_s.match?(YEN)

      amount = PriceConversion.amount_of(listing['price_original'].to_s).to_f
      amount.positive? && listing['price'] >= amount * 0.5
    end

    # Cada anuncio, en orden: del sitio y mercado correctos, no repetido, con el
    # precio convertido aquí (si se puede) y visitado por la búsqueda. `checks`
    # cuenta lo que se tiró, para avisarlo una sola vez.
    def sanitize_market(market, key, consulted, rates, checks)
      return nil unless market.is_a?(Hash)

      domains = AiLookupSources.domains(key)
      seen = Set.new
      listings = Array(market['listings']).filter_map do |listing|
        next unless listing.is_a?(Hash) && AiLookupSources.allowed?(listing['url'], key, within: domains)

        page = AiLookupSources.page_key(listing['url'])
        next unless seen.add?(page)

        price, converted_by, currency = PriceConversion.convert(listing, key, rates)
        drop = if converted_by == 'ia' && unconverted_yen?(listing) then :yen
               elsif !(price.is_a?(Numeric) && price.positive?) then :no_price
               elsif consulted.any? && consulted.exclude?(page) then :unvisited
               end
        if drop
          checks[drop] += 1
          next
        end

        verified = consulted.include?(page)
        checks[:unverified] += 1 unless verified
        listing.merge('price' => price.to_f, 'currency_original' => currency, 'converted_by' => converted_by,
                      'verified' => verified)
      end.first(MAX_LISTINGS)
      return nil if listings.empty?

      prices = listings.pluck('price')
      { 'min' => prices.min, 'max' => prices.max, 'currency' => PriceConversion::MARKET_CURRENCY[key],
        'sold' => price_range(listings.select { |l| l['sold'] == true }),
        'asking' => price_range(listings.reject { |l| l['sold'] == true }),
        'listings' => listings }
    end

    # Lo vendido es el precio real; lo que está en venta, lo que piden.
    def price_range(listings)
      return nil if listings.empty?

      prices = listings.pluck('price')
      { 'min' => prices.min, 'max' => prices.max, 'count' => prices.size }
    end

    def check_warnings(checks, consulted)
      warnings = []
      warnings << 'Se descartaron precios en yenes que no venían convertidos a USD.' if checks[:yen].positive?
      if checks[:unvisited].positive?
        warnings << "Se descartaron #{checks[:unvisited]} anuncio(s) que la búsqueda no visitó " \
                    '(enlaces posiblemente inventados).'
      end
      warnings << UNCONFIRMED_WARNING if consulted.empty? && checks[:unverified].positive?
      warnings
    end

    def cost_cents(input_tokens, output_tokens, searches)
      usd = (input_tokens / 1_000_000.0 * COST_INPUT_PER_M_USD) +
            (output_tokens / 1_000_000.0 * COST_OUTPUT_PER_M_USD) +
            (searches / 1000.0 * COST_PER_1K_SEARCHES_USD)
      (usd * 100).ceil
    end
  end
end
