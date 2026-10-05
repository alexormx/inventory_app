# frozen_string_literal: true

module Collectibles
  # Sitios en los que confiamos para precios. La IA puede buscar en toda la web
  # para identificar la pieza, pero el servidor tira cualquier anuncio de precio
  # que no sea de esta lista: un enlace inventado nunca llega a la pantalla.
  # México y el resto del mundo van separados porque el precio local y el
  # internacional se leen distinto.
  module AiLookupSources
    MX = %w[mercadolibre.com.mx amazon.com.mx].freeze
    WORLDWIDE = %w[ebay.com amazon.com amazon.co.jp hobbydb.com plazajapan.com hlj.com].freeze
    ALL = (MX + WORLDWIDE).freeze

    module_function

    def allowed?(url, market)
      domains = market == :mx ? MX : WORLDWIDE
      host = https_host(url)
      host.present? && domains.any? { |domain| host == domain || host.end_with?(".#{domain}") }
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
  end
end
