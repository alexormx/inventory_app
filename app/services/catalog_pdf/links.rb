# frozen_string_literal: true

require 'uri'

module CatalogPdf
  # Construye todos los enlaces públicos del catálogo en un solo lugar.
  module Links
    module_function

    SITE_URL = 'https://pasatiempos.com.mx'
    ORDER_MESSAGE = 'Hola, vi su catálogo de Pasatiempos y quiero hacer un pedido.'

    def whatsapp_url(number:, message: ORDER_MESSAGE)
      digits = number.to_s.gsub(/\D/, '')
      "https://wa.me/#{digits}?#{URI.encode_www_form(text: message)}"
    end

    def product_whatsapp_url(number:, code:, name:)
      whatsapp_url(number: number, message: "Hola, me interesa el producto #{code} — #{name}.")
    end

    def product_url(product)
      Rails.application.routes.url_helpers.product_url(product, host: 'pasatiempos.com.mx', protocol: 'https')
    end
  end
end
