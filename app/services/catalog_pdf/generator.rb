require 'base64'

module CatalogPdf
  # Renderiza la plantilla del catálogo a HTML y la convierte a PDF con Grover
  # (Puppeteer/Chromium). Pensado para correr SOLO en local: la gema 'grover'
  # vive en el grupo :development, así que no existe en producción/Heroku.
  # Por eso 'grover' se requiere de forma perezosa dentro de #to_pdf: el
  # eager_load de producción carga esta clase al arrancar, pero nunca llama
  # #to_pdf, así que jamás intenta cargar la gema ausente.
  class Generator
    LAUNCH_ARGS = ['--no-sandbox', '--disable-dev-shm-usage'].freeze
    LOGO_PATH = Rails.root.join('app/assets/images/logo.png')

    def initialize(title:, whatsapp_number:, items:)
      @title = title
      @whatsapp_number = whatsapp_number
      @items = items
    end

    def to_pdf
      require 'grover'
      Grover.new(html, **grover_options).to_pdf
    end

    def html
      ApplicationController.render(
        template: 'catalog_pdf/show',
        layout: false,
        locals: { title: @title, whatsapp_number: formatted_whatsapp, items: @items, logo: logo_data_uri }
      )
    end

    private

    # Formatea un número MX (52 + 10 dígitos) como "+52 33 8526 2707" para
    # mostrarlo en portada y pie de página. Si no calza el patrón, devuelve el
    # valor original sin tocar.
    def formatted_whatsapp
      digits = @whatsapp_number.to_s.gsub(/\D/, '')
      if digits.start_with?('52') && digits.length == 12
        rest = digits[2..]
        "+52 #{rest[0, 2]} #{rest[2, 4]} #{rest[6, 4]}"
      else
        @whatsapp_number
      end
    end

    def grover_options
      {
        format: 'Letter',
        print_background: true,
        launch_args: LAUNCH_ARGS,
        # El catálogo puede traer cientos de productos con imágenes embebidas en
        # base64: el HTML es enorme y a Chromium le toma más de los 30s default
        # parsear/maquetar (causaba "Navigation timeout of 30000 ms exceeded").
        # 'load' evita esperar a networkidle (no hay red: las imágenes son data URIs).
        wait_until: 'load',
        timeout: 180_000,
        # El HTML se sirve por interceptación de requests; la "URL" base solo se
        # usa para resolver recursos relativos. Por defecto Grover navega a
        # http://example.com, que en algunos entornos (ad-blockers, /etc/hosts,
        # DNS de WSL) se bloquea -> "net::ERR_BLOCKED_BY_CLIENT". Apuntar a
        # localhost evita ese bloqueo sin pegarle a la red (no hay recursos
        # remotos: imágenes y logo van embebidos en base64).
        display_url: 'http://localhost/catalogo',
        display_header_footer: true,
        header_template: header_template,
        footer_template: footer_template,
        margin: { top: '2.1cm', bottom: '1.1cm', left: '0.5cm', right: '0.5cm' }
      }
    end

    def header_template
      brand =
        if logo_data_uri
          %(<img src="#{logo_data_uri}" style="height:34px;" />)
        else
          '<span style="font-weight:bold; color:#c0392b; font-size:16px;">PASATIEMPOS</span>'
        end
      <<~HTML
        <div style="font-size:10px; width:100%; padding:4px 14px; box-sizing:border-box;
                    display:flex; justify-content:space-between; align-items:center;
                    border-bottom:2px solid #c0392b;">
          #{brand}
          <span class="title" style="font-weight:bold; color:#333; font-size:15px;"></span>
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
                    display:flex; justify-content:space-between; align-items:center; color:#777;">
          <span>Página <span class="pageNumber"></span> de <span class="totalPages"></span></span>
          <span style="font-weight:bold; color:#128C7E;">WhatsApp #{formatted_whatsapp}</span>
          <span>Pasatiempos</span>
        </div>
      HTML
    end
  end
end
