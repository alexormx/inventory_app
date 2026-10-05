# frozen_string_literal: true

module Collectibles
  # Búsqueda inversa de imagen con Google Cloud Vision (Web Detection): qué cree
  # Google que es la foto y en qué páginas aparece. Es lo que hace Google Lens y
  # lo que la IA no puede hacer sola (ella sólo busca texto).
  #
  # Nunca rompe la identificación: sin llave, con error o sin resultados
  # regresa nil y AiLookupService sigue sin este paso. La llave va sólo en el
  # encabezado X-Goog-Api-Key y nunca se registra.
  class ReverseImageSearch
    ENDPOINT = 'https://vision.googleapis.com/v1/images:annotate'
    TIMEOUT = 15
    MAX_GUESSES = 3
    MAX_ENTITIES = 8
    MAX_PAGES = 8
    TITLE_MAX = 150

    def self.api_key
      ENV.fetch('GOOGLE_VISION_API_KEY', nil)
    end

    def initialize(jpeg_bytes, api_key: self.class.api_key, connection: nil)
      @jpeg_bytes = jpeg_bytes
      @api_key = api_key
      @connection = connection
      @called = false
    end

    # true en cuanto se mandó la petición: es lo que Google cobra.
    def called?
      @called
    end

    def call
      return nil if @api_key.blank?

      @called = true
      response = connection.post(ENDPOINT) do |request|
        request.headers['X-Goog-Api-Key'] = @api_key
        request.headers['Content-Type'] = 'application/json'
        request.body = payload.to_json
      end
      body = JSON.parse(response.body.to_s)
      first = Array(body['responses']).first || {}
      error = body['error'] || first['error']
      return warn("status=#{response.status} #{error&.dig('message').to_s.truncate(200)}") if !response.success? || error

      trim(first['webDetection'] || {})
    rescue Faraday::Error, JSON::ParserError => e
      warn(e.class.name)
    end

    private

    def connection
      @connection ||= Faraday.new(request: { timeout: TIMEOUT, open_timeout: 5 })
    end

    def payload
      { requests: [{ image: { content: Base64.strict_encode64(@jpeg_bytes) },
                     features: [{ type: 'WEB_DETECTION', maxResults: 10 }] }] }
    end

    def trim(detection)
      guesses = Array(detection['bestGuessLabels']).filter_map { |g| g['label'].presence }.first(MAX_GUESSES)
      entities = Array(detection['webEntities'])
                 .select { |e| e['description'].present? }
                 .sort_by { |e| -e['score'].to_f }
                 .first(MAX_ENTITIES)
                 .map { |e| { 'description' => e['description'], 'score' => e['score'].to_f.round(2) } }
      pages = Array(detection['pagesWithMatchingImages'])
              .select { |page| AiLookupSources.https_host(page['url']).present? }
              .first(MAX_PAGES)
              .map { |page| { 'title' => page['pageTitle'].to_s.truncate(TITLE_MAX), 'url' => page['url'] } }
      return nil if guesses.empty? && entities.empty? && pages.empty?

      { 'best_guesses' => guesses, 'entities' => entities, 'pages' => pages }
    end

    def warn(detail)
      Rails.logger.warn("[ReverseImageSearch] Google Vision falló: #{detail}")
      nil
    end
  end
end
