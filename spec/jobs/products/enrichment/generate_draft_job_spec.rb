# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::Enrichment::GenerateDraftJob do
  include ActiveJob::TestHelper

  let(:errors) { Products::Enrichment::GenerateDraftService }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:draft) { create(:product_description_draft, product: product, status: :queued) }
  let(:service) { instance_double(Products::Enrichment::GenerateDraftService) }

  before { allow(Products::Enrichment::GenerateDraftService).to receive(:new).and_return(service) }

  def run_failing_with(error)
    allow(service).to receive(:call).and_raise(error)
    perform_enqueued_jobs { described_class.perform_later(draft.id) }
  rescue Minitest::UnexpectedError, errors::GenerationError
    nil # al agotar los reintentos el error sale del job (el helper de Rails lo envuelve)
  end

  it "reintenta una respuesta mal formada sólo una vez" do
    run_failing_with(errors::InvalidResponseError.new("roto"))
    expect(service).to have_received(:call).twice
  end

  it "reintenta un tropiezo de red hasta 3 veces" do
    run_failing_with(errors::TransientError.new("timeout"))
    expect(service).to have_received(:call).exactly(3).times
  end

  it "reintenta la saturación (429) hasta 5 veces" do
    run_failing_with(errors::RateLimitError.new("429"))
    expect(service).to have_received(:call).exactly(5).times
  end

  it "no reintenta un error inesperado" do
    run_failing_with(errors::GenerationError.new("boom"))
    expect(service).to have_received(:call).once
  end

  describe "reintentos viejos" do
    it "no genera si ya hay un borrador más nuevo del producto (se regeneró a mano)" do
      draft.update!(status: :failed)
      create(:product_description_draft, product: product, status: :queued)
      allow(service).to receive(:call)
      described_class.perform_now(draft.id)
      expect(service).not_to have_received(:call)
    end

    it "no genera un borrador rechazado" do
      draft.update!(status: :rejected)
      allow(service).to receive(:call)
      described_class.perform_now(draft.id)
      expect(service).not_to have_received(:call)
    end
  end

  describe ".enqueue_for" do
    it "crea un borrador en cola y lo encola" do
      expect { described_class.enqueue_for(product) }.to have_enqueued_job(described_class)
      expect(product.description_drafts.queued.count).to eq(1)
    end

    it "no duplica si ya hay un borrador pendiente" do
      create(:product_description_draft, product: product, status: :draft_generated)
      expect { described_class.enqueue_for(product) }.not_to have_enqueued_job(described_class)
    end
  end
end
