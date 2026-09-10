# frozen_string_literal: true

require 'rails_helper'

# La fase de release de Heroku corre DESPUÉS de construir el slug nuevo y ANTES
# de que los dynos web nuevos reciban tráfico. Si el comando sale distinto de
# cero, la release no llega a activarse y la anterior sigue sirviendo. Eso es lo
# que convierte "esquema primero, código después" en una propiedad del
# despliegue en vez de un procedimiento que alguien tiene que recordar.
#
# Estas expectativas se escriben por proceso a propósito, sin comparar la lista
# completa: así, cuando otra rama agregue un tipo de proceso propio (por ejemplo
# un worker), sólo tendrá que ajustar su propia regresión y no ésta.
RSpec.describe 'Heroku release phase' do
  subject(:processes) do
    Rails.root.join('Procfile').read.lines.filter_map do |line|
      stripped = line.strip
      next if stripped.empty?

      name, command = stripped.split(':', 2)
      [name.strip, command.to_s.strip]
    end
  end

  it 'declares exactly one release process' do
    expect(processes.count { |name, _| name == 'release' }).to eq(1)
  end

  it 'runs migrations as the release command' do
    release = processes.find { |name, _| name == 'release' }

    expect(release).not_to be_nil
    expect(release.last).to eq('bundle exec rails db:migrate')
  end

  it 'leaves the canonical web command untouched' do
    web = processes.find { |name, _| name == 'web' }

    expect(web).not_to be_nil
    expect(web.last).to eq('bundle exec puma -C config/puma.rb')
  end

  it 'applies the schema before the web process is declared' do
    names = processes.map(&:first)

    # El orden del Procfile no es lo que Heroku obedece —lo hace la fase de
    # release—, pero mantenerlo alineado con el contrato evita leer el archivo
    # como si web arrancara primero.
    expect(names.index('release')).to be < names.index('web')
  end
end
