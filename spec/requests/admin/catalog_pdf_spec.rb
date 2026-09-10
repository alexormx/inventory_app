# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Catalog PDF', type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    sign_in admin
    # `ensure_local!` bloquea todo fuera de development; en test lo saltamos
    # para poder ejercitar el controlador a través del stack real.
    allow_any_instance_of(Admin::CatalogPdfController).to receive(:ensure_local!)
  end

  describe 'POST generate' do
    it 'rejects a request with no output formats selected' do
      post admin_catalog_pdf_generate_path, params: { formats: [] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to be_present
    end

    it 'ignores unknown formats and rejects when nothing valid remains' do
      post admin_catalog_pdf_generate_path, params: { formats: ['bogus'] }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # "Mostrar fecha de lanzamiento" viaja del formulario al Generator. El fallo
  # anterior: la opción se leía de `params` DENTRO del hilo de fondo, ya
  # desligado del ciclo de la petición, así que llegaba en falso a la
  # generación. Ahora se captura en el hilo de la petición y se pasa explícito
  # por generate -> run_generation -> build_artifacts -> pdf_bytes -> Generator.
  describe 'POST generate — include_launch_date propagation' do
    let(:pdf_double) { instance_double(CatalogPdf::Generator, to_pdf: 'PDF-BYTES') }
    let(:builder_double) { instance_double(CatalogPdf::Builder) }
    let(:sample_items) do
      [{ code: 'A1', name: 'Uno', brand: 'Tomica', series: 'Premium', scale: nil,
         price: 100, event: nil, event_label: nil,
         launch_date: '2026-03-04T10:30:00-06:00',
         product_url: 'https://pasatiempos.com.mx/products/uno', unique_piece: false }]
    end

    before do
      allow(CatalogPdf::Builder).to receive(:new).and_return(builder_double)
      allow(builder_double).to receive(:items).and_return(sample_items)
      allow(CatalogPdf::Generator).to receive(:new).and_return(pdf_double)
    end

    after { Dir.glob(Rails.root.join('tmp/catalog_*.pdf')).each { |file| File.delete(file) } }

    # Corre la generación en línea pero registrando el orden real de las
    # llamadas, para poder afirmar que la bandera se evalúa ANTES del hilo.
    def run_generate(extra_params)
      order = []
      allow_any_instance_of(Admin::CatalogPdfController)
        .to receive(:include_launch_date?).and_wrap_original do |original|
          order << :flag_evaluated
          original.call
        end
      allow(Thread).to receive(:new) do |&block|
        order << :background_job_started
        block&.call
        instance_double(Thread)
      end
      post admin_catalog_pdf_generate_path, params: { formats: ['pdf_landscape'] }.merge(extra_params)
      order
    end

    it 'evaluates the flag in the request thread, before the background job runs' do
      order = run_generate(include_launch_date: '1')

      expect(response).to have_http_status(:ok)
      expect(order.index(:flag_evaluated)).to be < order.index(:background_job_started)
    end

    it 'passes include_launch_date: true to the generator when the box is checked' do
      run_generate(include_launch_date: '1')

      expect(CatalogPdf::Generator).to have_received(:new)
        .with(hash_including(include_launch_date: true)).at_least(:once)
    end

    it 'passes include_launch_date: false when the param is absent' do
      run_generate({})

      expect(CatalogPdf::Generator).to have_received(:new)
        .with(hash_including(include_launch_date: false)).at_least(:once)
    end

    it 'passes include_launch_date: false for an explicit "0"' do
      run_generate(include_launch_date: '0')

      expect(CatalogPdf::Generator).to have_received(:new)
        .with(hash_including(include_launch_date: false)).at_least(:once)
    end

    it 'keeps the option independent from "Priorizar lanzamientos recientes"' do
      run_generate(include_launch_date: '1', prioritize_new: '0')

      expect(CatalogPdf::Generator).to have_received(:new)
        .with(hash_including(include_launch_date: true)).at_least(:once)
    end
  end

  describe 'GET download' do
    around do |example|
      example.run
    ensure
      CatalogPdf::Progress.delete(@job_id) if @job_id
      File.delete(@path) if @path && File.exist?(@path)
    end

    def seed_job(basename:, content_type:, filename:)
      @job_id = CatalogPdf::Progress.start
      @path = Rails.root.join('tmp', basename)
      File.binwrite(@path, 'fake-bytes')
      CatalogPdf::Progress.update(@job_id, status: 'done', path: @path.to_s,
                                           filename: filename, content_type: content_type)
    end

    # Antes el PDF se servía `inline` y el navegador lo abría en una pestaña.
    # Ahora el catálogo terminado se descarga a la PC, así que ambos formatos
    # viajan como adjunto y con el nombre que decide el servidor.
    it 'serves a single PDF as an attachment' do
      seed_job(basename: "catalog_test_#{SecureRandom.hex(4)}.pdf",
               content_type: 'application/pdf', filename: 'catalogo.pdf')

      get admin_catalog_pdf_download_path, params: { job_id: @job_id }

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq('application/pdf')
        expect(response.headers['Content-Disposition']).to include('attachment')
        expect(response.headers['Content-Disposition']).not_to include('inline')
        expect(response.headers['Content-Disposition']).to include('catalogo.pdf')
      end
    end

    it 'serves a multi-format ZIP as an attachment' do
      seed_job(basename: "catalog_test_#{SecureRandom.hex(4)}.zip",
               content_type: 'application/zip', filename: 'catalogo.zip')

      get admin_catalog_pdf_download_path, params: { job_id: @job_id }

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('application/zip')
      expect(response.headers['Content-Disposition']).to include('attachment')
    end

    it 'returns 404 for an unknown job' do
      get admin_catalog_pdf_download_path, params: { job_id: 'nope' }

      expect(response).to have_http_status(:not_found)
    end
  end
end
