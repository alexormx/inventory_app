# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookupJob do
  include ActiveJob::TestHelper

  let(:lookup) do
    Collectibles::AiLookup.new(user: create(:user, :admin)).tap do |l|
      l.photos.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
      l.save!
    end
  end

  let(:service) { instance_double(Collectibles::AiLookupService) }

  before { allow(Collectibles::AiLookupService).to receive(:new).and_return(service) }

  it 'guarda resultado, uso y costo' do
    allow(service).to receive(:call).and_return(
      Collectibles::AiLookupService::Result.new(data: { 'identification' => {} }, tokens_input: 10,
                                                tokens_output: 5, web_search_calls: 2, cost_cents: 6)
    )
    described_class.perform_now(lookup.id)

    lookup.reload
    expect(lookup).to be_done
    expect(lookup.result).to eq('identification' => {})
    expect(lookup.slice(:tokens_input, :tokens_output, :web_search_calls, :estimated_cost_cents).values).to eq([10, 5, 2, 6])
    expect(lookup.ai_model).to eq('gpt-4.1')
    expect(lookup.finished_at).to be_present
  end

  it 'marca fallida con el motivo ante un error de la IA y no reintenta' do
    allow(service).to receive(:call).and_raise(Collectibles::AiLookupService::Error, 'Respuesta vacía de OpenAI')
    described_class.perform_now(lookup.id)

    expect(lookup.reload).to be_failed
    expect(lookup.error_message).to include('Respuesta vacía')
    expect(enqueued_jobs.pluck(:job)).not_to include(described_class)
  end

  it 'reintenta el 429 y al agotar los intentos marca fallida' do
    allow(service).to receive(:call).and_raise(Collectibles::AiLookupService::RateLimitError, '429')

    perform_enqueued_jobs { described_class.perform_later(lookup.id) }

    expect(service).to have_received(:call).exactly(4).times
    expect(lookup.reload).to be_failed
    expect(lookup.error_message).to include('saturado')
  end

  it 'no paga una búsqueda que la pantalla ya dio por fallida' do
    allow(service).to receive(:call)
    lookup.update_columns(created_at: 4.minutes.ago)
    described_class.perform_now(lookup.id)

    expect(service).not_to have_received(:call)
    expect(lookup.reload).to be_failed
    expect(lookup.error_message).to include('tardó demasiado')
  end

  it 'no repite una búsqueda ya terminada' do
    lookup.update!(status: :done)
    allow(service).to receive(:call)
    described_class.perform_now(lookup.id)
    expect(service).not_to have_received(:call)
  end
end
