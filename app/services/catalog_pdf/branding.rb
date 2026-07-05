require 'base64'

module CatalogPdf
  # Recursos de marca compartidos por el generador de PDF y el de imágenes:
  # el logo embebido en base64 y el formato del número de WhatsApp.
  module Branding
    module_function

    LOGO_PATH = Rails.root.join('app/assets/images/logo.png')

    def logo_data_uri
      @logo_data_uri ||= "data:image/png;base64,#{Base64.strict_encode64(File.binread(LOGO_PATH))}"
    rescue StandardError
      nil
    end

    # Formatea un número MX (52 + 10 dígitos) como "+52 33 8526 2707". Si no
    # calza el patrón, devuelve el valor original sin tocar.
    def format_whatsapp(number)
      digits = number.to_s.gsub(/\D/, '')
      if digits.start_with?('52') && digits.length == 12
        rest = digits[2..]
        "+52 #{rest[0, 2]} #{rest[2, 4]} #{rest[6, 4]}"
      else
        number
      end
    end
  end
end
