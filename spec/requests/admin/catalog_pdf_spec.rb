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

    it 'serves a single PDF inline' do
      seed_job(basename: "catalog_test_#{SecureRandom.hex(4)}.pdf",
               content_type: 'application/pdf', filename: 'catalogo.pdf')

      get admin_catalog_pdf_download_path, params: { job_id: @job_id }

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('application/pdf')
      expect(response.headers['Content-Disposition']).to include('inline')
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
