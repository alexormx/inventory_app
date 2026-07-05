# frozen_string_literal: true

module Admin
  # Página para generar el catálogo PDF desde el admin. SOLO corre en local:
  # depende de Grover/Puppeteer, que viven en el grupo :development y no existen
  # en producción. `ensure_local!` bloquea cualquier acceso fuera de desarrollo.
  class CatalogPdfController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :ensure_local!
    layout 'admin'

    def show; end

    # Lista de series de la fuente elegida (para poblar la UI sin generar
    # todavía el PDF).
    def series
      render json: { series: builder.series_summary }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # Arranca la generación en un hilo de fondo y devuelve un job_id. La UI
    # sondea `progress` y al terminar abre `download`.
    ALLOWED_FORMATS = %w[pdf_portrait pdf_landscape images].freeze

    def generate
      formats = selected_formats
      return render json: { error: 'Selecciona al menos un formato.' }, status: :unprocessable_entity if formats.empty?

      builder_for_job = builder
      title = catalog_title
      number = Rails.application.config.whatsapp_number
      rate = usd_rate
      job_id = CatalogPdf::Progress.start

      Thread.new do
        Rails.application.executor.wrap do
          run_generation(job_id, builder_for_job, title, number, rate, formats)
        end
      end

      render json: { job_id: job_id }
    end

    # Estado actual del job (para la barra de progreso).
    def progress
      state = CatalogPdf::Progress.fetch(params[:job_id])
      return head(:not_found) unless state

      render json: state.except(:path)
    end

    # Sirve el archivo generado (PDF o ZIP) una vez que el job terminó.
    def download
      state = CatalogPdf::Progress.fetch(params[:job_id])
      unless state && state[:status] == 'done' && state[:path] && File.exist?(state[:path])
        return head(:not_found)
      end

      content_type = state[:content_type] || 'application/pdf'
      disposition = content_type == 'application/pdf' ? 'inline' : 'attachment'
      send_data File.binread(state[:path]), filename: state[:filename] || 'catalogo.pdf',
                                             type: content_type, disposition: disposition
    end

    private

    def run_generation(job_id, builder, title, number, rate, formats)
      CatalogPdf::Progress.update(job_id, status: 'building', name: 'Conectando con la fuente de datos…')
      items = builder.items do |current, total, name|
        CatalogPdf::Progress.update(job_id, status: 'building', current: current, total: total, name: name)
      end

      if items.empty?
        CatalogPdf::Progress.update(job_id, status: 'error', error: 'No hay productos para las series seleccionadas.')
        return
      end

      # Los items (con imágenes descargadas) se construyen una sola vez y se
      # reutilizan para cada formato seleccionado.
      artifacts = build_artifacts(job_id, items, title, number, rate, formats)
      path, filename, content_type = finalize_artifacts(job_id, artifacts)
      CatalogPdf::Progress.update(job_id, status: 'done', path: path.to_s, filename: filename, content_type: content_type)
    rescue StandardError => e
      CatalogPdf::Progress.update(job_id, status: 'error', error: e.message)
    end

    # Genera cada formato pedido y devuelve [[nombre_en_zip, bytes], ...].
    def build_artifacts(job_id, items, title, number, rate, formats)
      artifacts = []

      if formats.include?('pdf_portrait')
        CatalogPdf::Progress.update(job_id, status: 'rendering', name: 'Generando PDF vertical…')
        artifacts << ['catalogo_vertical.pdf', pdf_bytes(title, number, items, rate, :portrait)]
      end

      if formats.include?('pdf_landscape')
        CatalogPdf::Progress.update(job_id, status: 'rendering', name: 'Generando PDF horizontal…')
        artifacts << ['catalogo_horizontal.pdf', pdf_bytes(title, number, items, rate, :landscape)]
      end

      if formats.include?('images')
        pngs = CatalogPdf::ImageGenerator.new(title: title, whatsapp_number: number, items: items, usd_rate: rate)
                                         .to_pngs do |current, total|
          CatalogPdf::Progress.update(job_id, status: 'rendering', name: "Generando imagen #{current}/#{total}…")
        end
        pngs.each { |name, bytes| artifacts << ["imagenes/#{name}", bytes] }
      end

      artifacts
    end

    def pdf_bytes(title, number, items, rate, orientation)
      CatalogPdf::Generator.new(title: title, whatsapp_number: number, items: items,
                                usd_rate: rate, orientation: orientation).to_pdf
    end

    # Un solo PDF se sirve tal cual; cualquier otra combinación (imágenes o
    # varios archivos) se empaqueta en un ZIP.
    def finalize_artifacts(job_id, artifacts)
      if artifacts.size == 1 && artifacts.first.first.end_with?('.pdf')
        path = Rails.root.join('tmp', "catalog_#{job_id}.pdf")
        File.binwrite(path, artifacts.first.last)
        [path, download_filename('pdf'), 'application/pdf']
      else
        require 'zip'
        path = Rails.root.join('tmp', "catalog_#{job_id}.zip")
        Zip::OutputStream.open(path) do |zos|
          artifacts.each do |name, bytes|
            zos.put_next_entry(name)
            zos.write(bytes)
          end
        end
        [path, download_filename('zip'), 'application/zip']
      end
    end

    def ensure_local!
      head :not_found unless Rails.env.development?
    end

    def builder
      CatalogPdf::Builder.new(
        source: params[:source],
        series: params[:series],
        sort: params[:sort],
        direction: params[:direction],
        api_url: api_url,
        api_token: api_token
      )
    end

    def api_url
      params[:api_url].presence || ENV.fetch('CATALOG_API_URL', 'https://pasatiempos.com.mx')
    end

    def api_token
      params[:api_token].presence || ENV['CATALOG_API_TOKEN']
    end

    # Tipo de cambio (MXN por USD) para mostrar el precio en USD. nil si el
    # admin no marcó la opción o el valor no es positivo.
    def usd_rate
      return nil unless ActiveModel::Type::Boolean.new.cast(params[:include_usd])

      rate = params[:usd_rate].to_f
      rate.positive? ? rate : nil
    end

    def catalog_title
      params[:title].presence || "CATÁLOGO #{I18n.l(Date.today, format: '%B %Y').upcase}"
    end

    def selected_formats
      Array(params[:formats]).map(&:to_s) & ALLOWED_FORMATS
    end

    def download_filename(ext)
      "catalogo_#{Time.zone.now.strftime('%Y%m%d_%H%M%S')}.#{ext}"
    end
  end
end
