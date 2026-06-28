require 'net/http'
require 'uri'
require 'json'
require 'base64'

module CatalogPdf
  # Trae los ítems del catálogo desde la app en producción (vía el endpoint
  # /api/v1/catalog, autenticado con el api_token de un admin) y los deja listos
  # para el Generator: descarga cada imagen y la embebe como data URI.
  #
  # Pensado para correr en LOCAL: la PC del usuario pide los datos al servidor
  # y arma el PDF con Grover (que no vive en producción).
  module RemoteSource
    module_function

    MAX_REDIRECTS = 5

    # Ítems listos para el Generator (imagen embebida en base64).
    def items(base_url:, token:)
      metadata(base_url: base_url, token: token).map { |item| embed_item(item) }
    end

    # Metadata sin descargar imágenes (solo la URL). Barato: una sola petición.
    # Útil para listar series o filtrar antes de bajar imágenes.
    def metadata(base_url:, token:)
      payload = fetch_json(URI.join(base_url, '/api/v1/catalog'), token)
      payload.fetch('items').map { |item| normalize(item) }
    end

    # Descarga la imagen del ítem y la deja embebida en :image.
    def embed_item(item)
      item.except(:image_url).merge(image: embed_image(item[:image_url]))
    end

    def fetch_json(uri, token)
      uri = URI(uri)
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{token}"
      req['Accept'] = 'application/json'
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
      unless res.is_a?(Net::HTTPSuccess)
        raise "Catalog API respondió #{res.code}: #{res.body.to_s[0, 300]}"
      end

      JSON.parse(res.body)
    end

    def normalize(item)
      {
        code: item['code'],
        name: item['name'],
        brand: item['brand'],
        series: item['series'].presence || 'Sin serie',
        scale: item['scale'].presence,
        price: item['price'],
        badges: Array(item['badges']),
        image_url: item['image_url']
      }
    end

    # Descarga la imagen y la embebe en base64. Si falla, deja la URL original
    # para que Chromium intente bajarla al renderizar.
    def embed_image(url)
      return nil if url.to_s.strip.empty?

      res = get_following_redirects(URI(url))
      return url unless res.is_a?(Net::HTTPSuccess)

      content_type = res['Content-Type'].to_s.split(';').first.presence || 'image/jpeg'
      "data:#{content_type};base64,#{Base64.strict_encode64(res.body)}"
    rescue StandardError
      url
    end

    def get_following_redirects(uri, limit: MAX_REDIRECTS)
      raise 'Demasiados redirects al descargar imagen' if limit <= 0

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      case res
      when Net::HTTPRedirection
        get_following_redirects(URI.join(uri.to_s, res['Location']), limit: limit - 1)
      else
        res
      end
    end
  end
end
