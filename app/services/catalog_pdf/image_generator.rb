module CatalogPdf
  # Renderiza el catálogo como imágenes descargables (una PNG por página) para
  # publicar en Facebook. Reutiliza el diseño de tarjetas del PDF pero en un
  # lienzo fijo de 1080x1350 px (relación 4:5, ideal para el feed). Igual que el
  # Generator, corre SOLO en local (depende de Grover/Chromium) y carga la gema
  # de forma perezosa.
  class ImageGenerator
    LAUNCH_ARGS = Generator::LAUNCH_ARGS
    TRANSIENT_RENDER_ERROR = Generator::TRANSIENT_RENDER_ERROR
    MAX_RENDER_ATTEMPTS = 3
    PER_SHEET = 6
    WIDTH = 1080
    HEIGHT = 1350

    def initialize(title:, whatsapp_number:, items:, usd_rate: nil)
      @title = title
      @whatsapp_number = Branding.format_whatsapp(whatsapp_number)
      @items = items
      @usd_rate = usd_rate
    end

    # Devuelve un arreglo de [nombre_archivo, bytes_png], una imagen por página.
    # Si se pasa un bloque, se invoca con (current, total) para reportar progreso.
    def to_pngs
      require 'grover'
      pages = @items.each_slice(PER_SHEET).to_a
      total = pages.size
      pages.each_with_index.map do |group, i|
        yield(i + 1, total) if block_given?
        [format('catalogo_%02d.png', i + 1), render_png(group, i + 1, total)]
      end
    end

    private

    def render_png(group, page, total)
      html = html_for(group, page, total)
      attempt = 0
      begin
        attempt += 1
        Grover.new(html, **grover_options).to_png
      rescue StandardError => e
        raise unless attempt < MAX_RENDER_ATTEMPTS && e.message.to_s.match?(TRANSIENT_RENDER_ERROR)

        sleep(attempt)
        retry
      end
    end

    def html_for(group, page, total)
      ApplicationController.render(
        template: 'catalog_pdf/image_sheet',
        layout: false,
        locals: { title: @title, whatsapp_number: @whatsapp_number, items: group,
                  logo: Branding.logo_data_uri, usd_rate: @usd_rate, page: page, total_pages: total }
      )
    end

    def grover_options
      {
        viewport: { width: WIDTH, height: HEIGHT },
        full_page: false,
        print_background: true,
        launch_args: LAUNCH_ARGS,
        wait_until: 'load',
        timeout: 120_000,
        display_url: 'http://localhost/catalogo'
      }
    end
  end
end
