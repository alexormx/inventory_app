# frozen_string_literal: true

module Images
  # Prepara una foto para mandarla a un modelo de IA: lado mayor ≤ 1024 px,
  # JPEG y sin metadatos (`-strip` quita EXIF/GPS y comentarios). Lo usan la
  # identificación de quick_add y la generación de descripciones.
  module AiReadyJpeg
    class InvalidImage < StandardError; end

    MAX_EDGE = 1024
    # Pide a libjpeg decodificar ya reducido (al menos 2× el tamaño final, para
    # no perder nitidez). Los topes de memoria de ImageMagick van en
    # config/initializers/image_magick_limits.rb.
    JPEG_DECODE_SIZE = "#{MAX_EDGE * 2}x#{MAX_EDGE * 2}".freeze

    module_function

    def call(attachment)
      attachment.blob.open do |file|
        resized = ImageProcessing::MiniMagick.source(file.path)
                                             .loader(define: { jpeg: { size: JPEG_DECODE_SIZE } })
                                             .resize_to_limit(MAX_EDGE, MAX_EDGE)
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
      raise InvalidImage, e.message.lines.first.to_s.strip
    end
  end
end
