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
    def generate
      builder_for_job = builder
      title = catalog_title
      number = Rails.application.config.whatsapp_number
      filename = pdf_filename
      job_id = CatalogPdf::Progress.start

      Thread.new do
        Rails.application.executor.wrap do
          run_generation(job_id, builder_for_job, title, number, filename)
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

    # Sirve el PDF generado una vez que el job terminó.
    def download
      state = CatalogPdf::Progress.fetch(params[:job_id])
      unless state && state[:status] == 'done' && state[:path] && File.exist?(state[:path])
        return head(:not_found)
      end

      send_data File.binread(state[:path]), filename: state[:filename] || 'catalogo.pdf',
                                             type: 'application/pdf', disposition: 'inline'
    end

    private

    def run_generation(job_id, builder, title, number, filename)
      CatalogPdf::Progress.update(job_id, status: 'building', name: 'Conectando con la fuente de datos…')
      items = builder.items do |current, total, name|
        CatalogPdf::Progress.update(job_id, status: 'building', current: current, total: total, name: name)
      end

      if items.empty?
        CatalogPdf::Progress.update(job_id, status: 'error', error: 'No hay productos para las series seleccionadas.')
        return
      end

      CatalogPdf::Progress.update(job_id, status: 'rendering', name: 'Generando PDF…')
      pdf = CatalogPdf::Generator.new(title: title, whatsapp_number: number, items: items).to_pdf

      path = Rails.root.join('tmp', "catalog_#{job_id}.pdf")
      File.binwrite(path, pdf)
      CatalogPdf::Progress.update(job_id, status: 'done', path: path.to_s, filename: filename)
    rescue StandardError => e
      CatalogPdf::Progress.update(job_id, status: 'error', error: e.message)
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

    def catalog_title
      params[:title].presence || "CATÁLOGO #{I18n.l(Date.today, format: '%B %Y').upcase}"
    end

    def pdf_filename
      "catalogo_#{Time.zone.now.strftime('%Y%m%d_%H%M%S')}.pdf"
    end
  end
end
