# frozen_string_literal: true

require 'rails_helper'

# El Procfile es el contrato de procesos con Heroku. Estas pruebas fijan la
# separación: Puma sólo sirve web, un worker dedicado corre Solid Queue, y el
# supervisor dentro de Puma sigue existiendo únicamente como palanca de reversa
# (revertir es volver a poner la variable de entorno, sin desplegar código).
RSpec.describe 'Solid Queue process model' do
  let(:procfile) { Rails.root.join('Procfile').read.lines.map(&:strip).reject(&:empty?) }
  let(:process_types) { procfile.map { |line| line.split(':', 2).first } }

  describe 'Procfile' do
    it 'declares release, web and exactly one worker process type' do
      expect(process_types).to eq(%w[release web worker])
    end

    it 'keeps the release phase running migrations' do
      expect(procfile).to include('release: bundle exec rails db:migrate')
    end

    it 'keeps Puma as the web process' do
      expect(procfile).to include('web: bundle exec puma -C config/puma.rb')
    end

    # bin/jobs es el punto de entrada canónico que instala el generador de
    # solid_queue; a diferencia de `rake solid_queue:start` acepta banderas como
    # --skip-recurring, necesarias si algún día se agrega un segundo worker.
    it 'runs the dedicated worker through the canonical Solid Queue entry point' do
      expect(procfile).to include('worker: bundle exec bin/jobs')
    end
  end

  describe 'bin/jobs' do
    subject(:jobs_bin) { Rails.root.join('bin/jobs') }

    it 'exists and is executable' do
      aggregate_failures do
        expect(jobs_bin.exist?).to be true
        expect(jobs_bin.executable?).to be true
      end
    end

    it 'starts the Solid Queue supervisor through its CLI' do
      expect(jobs_bin.read).to include('SolidQueue::Cli.start')
    end
  end

  describe 'in-Puma supervisor' do
    it 'remains available behind SOLID_QUEUE_IN_PUMA as the rollback lever' do
      expect(Rails.root.join('config/puma.rb').read)
        .to include("plugin :solid_queue if ENV['SOLID_QUEUE_IN_PUMA']")
    end
  end

  describe 'config/queue.yml' do
    subject(:queue_config) do
      YAML.load_file(Rails.root.join('config/queue.yml'), aliases: true).fetch('production')
    end

    it 'runs exactly one conservative worker alongside one dispatcher' do
      aggregate_failures do
        expect(queue_config['workers'].size).to eq(1)
        expect(queue_config['dispatchers'].size).to eq(1)
        expect(queue_config['workers'].first['processes']).to eq(1)
        expect(queue_config['workers'].first['queues']).to eq('*')
      end
    end

    # SolidQueue::Configuration#ensure_correctly_sized_thread_pool aborta el
    # arranque si (hilos + 2) supera el pool de ActiveRecord.
    it 'keeps worker threads within the ActiveRecord connection pool' do
      threads = queue_config['workers'].first['threads']

      expect(threads + 2).to be <= ActiveRecord::Base.connection_pool.size
    end
  end
end
