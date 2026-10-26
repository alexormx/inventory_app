# frozen_string_literal: true

module Collectibles
  # Sitios en los que confiamos para precios: los de las guías de búsqueda
  # (LookupSource, editables en el admin). La IA puede buscar en toda la web
  # para identificar la pieza, pero el servidor tira cualquier anuncio de
  # precio que no sea de estos sitios: un enlace inventado nunca llega a la
  # pantalla. México y el resto del mundo van separados porque el precio local
  # y el internacional se leen distinto.
  module AiLookupSources
    module_function

    def domains(market)
      LookupSource.price_domains(market)
    end

    # `within` (los dominios) se puede pasar ya leído para no consultar la base por anuncio.
    def allowed?(url, market, within: nil)
      host = https_host(url)
      host.present? && (within || domains(market)).any? { |domain| host == domain || host.end_with?(".#{domain}") }
    end

    def allowed_anywhere?(url)
      allowed?(url, :mx) || allowed?(url, :world)
    end

    def https_host(url)
      uri = URI.parse(url.to_s)
      return nil unless uri.is_a?(URI::HTTP)

      uri.host.to_s.downcase
    rescue URI::InvalidURIError
      nil
    end

    # La misma página escrita de otra forma: sin esquema, «www.», parámetros,
    # ancla ni diagonal final. «https://www.ebay.com/itm/1?hash=x» → «ebay.com/itm/1».
    def page_key(url)
      host = https_host(url)
      return nil if host.blank?

      path = URI.parse(url.to_s).path.to_s.chomp('/')
      "#{host.delete_prefix('www.')}#{path}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
