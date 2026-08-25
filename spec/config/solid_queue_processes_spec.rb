# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SolidQueue do
  subject(:processes) { Rails.root.join('Procfile').read.lines.map(&:strip).reject(&:empty?) }

  let(:expected_processes) do
    [
      'web: bundle exec puma -C config/puma.rb',
      'worker: bundle exec rake solid_queue:start'
    ]
  end

  it 'keeps the canonical web process and declares exactly one dedicated worker type' do
    expect(processes).to eq(expected_processes)
  end

  it 'keeps the in-Puma supervisor as an explicitly removable fallback' do
    puma_config = Rails.root.join('config/puma.rb').read

    expect(puma_config).to include("plugin :solid_queue if ENV['SOLID_QUEUE_IN_PUMA']")
  end
end
