# frozen_string_literal: true

require 'base64'

module CatalogPdf
  # Prepara copias exclusivas del PDF. Las tarjetas imprimen la foto a menos de
  # 4 cm, por lo que 280 px conservan más de 190 ppp sin cargar el original en
  # Chromium. Nunca modifica el blob ni las variantes usadas por la tienda.
  module ImageEncoder
    module_function

    MAX_IMAGE_PX = 280
    JPEG_QUALITY = 62

    def data_uri(bytes)
      require 'vips'
      image = Vips::Image.thumbnail_buffer(bytes, MAX_IMAGE_PX)
      image = image.flatten(background: [255, 255, 255]) if image.has_alpha?
      encoded = image.jpegsave_buffer(Q: JPEG_QUALITY, strip: true, optimize_coding: true)
      "data:image/jpeg;base64,#{Base64.strict_encode64(encoded)}"
    rescue StandardError
      nil
    end
  end
end
