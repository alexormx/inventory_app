require 'grover'
require 'base64'

module CatalogPdf
  # Renderiza la plantilla del catálogo a HTML y la convierte a PDF con Grover
  # (Puppeteer/Chromium). Pensado para correr SOLO en local: la gema 'grover'
  # vive en el grupo :development, así que no existe en producción/Heroku.
  class Generator
    LAUNCH_ARGS = ['--no-sandbox', '--disable-dev-shm-usage'].freeze
    LOGO_PATH = Rails.root.join('app/assets/images/logo.png')

    def initialize(title:, whatsapp_number:, items:)
      @title = title
      @whatsapp_number = whatsapp_number
      @items = items
    end

    def to_pdf
      Grover.new(html, **grover_options).to_pdf
    end

    def html
      ApplicationController.render(
        template: 'catalog_pdf/show',
        layout: false,
        locals: { title: @title, whatsapp_number: @whatsapp_number, items: @items, logo: logo_data_uri }
      )
    end

    private

    def grover_options
      {
        format: 'A4',
        print_background: true,
        launch_args: LAUNCH_ARGS,
        display_header_footer: true,
        header_template: header_template,
        footer_template: footer_template,
        margin: { top: '2.1cm', bottom: '1.1cm', left: '0.5cm', right: '0.5cm' }
      }
    end

    def header_template
      brand =
        if logo_data_uri
          %(<img src="#{logo_data_uri}" style="height:22px;" />)
        else
          '<span style="font-weight:bold; color:#c0392b;">PASATIEMPOS</span>'
        end
      <<~HTML
        <div style="font-size:10px; width:100%; padding:4px 14px; box-sizing:border-box;
                    display:flex; justify-content:space-between; align-items:center;
                    border-bottom:2px solid #c0392b;">
          #{brand}
          <span class="title" style="font-weight:bold; color:#333;"></span>
          <span style="color:#999;">Coleccionables</span>
        </div>
      HTML
    end

    def logo_data_uri
      @logo_data_uri ||= "data:image/png;base64,#{Base64.strict_encode64(File.binread(LOGO_PATH))}"
    rescue StandardError
      nil
    end

    def footer_template
      <<~HTML
        <div style="font-size:9px; width:100%; padding:2px 14px; box-sizing:border-box;
                    text-align:center; color:#777;">
          Página <span class="pageNumber"></span> de <span class="totalPages"></span> — Pasatiempos
        </div>
      HTML
    end
  end
end
