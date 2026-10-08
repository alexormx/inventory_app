# frozen_string_literal: true

module Images
  # Prepara una foto para mandarla a un modelo de IA: lado mayor ≤ 1024 px,
  # JPEG y sin metadatos (`-strip` quita EXIF/GPS y comentarios). Lo usan la
  # identificación de quick_add y la generación de descripciones.
  module AiReadyJpeg
    class InvalidImage < StandardError; end

    MAX_EDGE = 1024

    module_function

    def call(attachment)
      attachment.blob.open do |file|
        resized = ImageProcessing::MiniMagick.source(file.path)
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
