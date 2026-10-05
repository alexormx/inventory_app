# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookup do
  let(:admin) { create(:user, :admin) }

  def attach(lookup, filename:, content_type:, io: File.open(Rails.root.join('spec/fixtures/files/test1.png')))
    lookup.photos.attach(io: io, filename: filename, content_type: content_type)
    lookup
  end

  it 'acepta una imagen PNG' do
    lookup = attach(described_class.new(user: admin), filename: 'a.png', content_type: 'image/png')
    expect(lookup).to be_valid
  end

  it 'exige foto' do
    expect(described_class.new(user: admin)).not_to be_valid
  end

  it 'rechaza HEIC con un mensaje que dice qué formatos sirven' do
    lookup = attach(described_class.new(user: admin), filename: 'a.heic', content_type: 'image/heic',
                                                      io: StringIO.new('fake heic'))
    expect(lookup).not_to be_valid
    expect(lookup.errors.full_messages.join).to include('JPG, PNG, WEBP o GIF')
  end

  it 'rechaza fotos de más del tope' do
    stub_const('Collectibles::AiLookup::MAX_PHOTO_BYTES', 10)
    lookup = attach(described_class.new(user: admin), filename: 'a.png', content_type: 'image/png')
    expect(lookup).not_to be_valid
    expect(lookup.errors.full_messages.join).to include('15 MB')
  end

  describe '.daily_limit_reached?' do
    it 'cuenta las búsquedas de hoy de todos los usuarios' do
      stub_const('Collectibles::AiLookup::DAILY_LIMIT', 2)
      2.times { attach(described_class.new(user: create(:user, :admin)), filename: 'a.png', content_type: 'image/png').save! }
      expect(described_class.daily_limit_reached?).to be(true)
    end

    it 'no cuenta las de ayer' do
      stub_const('Collectibles::AiLookup::DAILY_LIMIT', 1)
      travel_to(1.day.ago) { attach(described_class.new(user: admin), filename: 'a.png', content_type: 'image/png').save! }
      expect(described_class.daily_limit_reached?).to be(false)
    end
  end

  describe '#as_status_json' do
    let(:lookup) { attach(described_class.new(user: admin), filename: 'a.png', content_type: 'image/png').tap(&:save!) }

    it 'reporta como fallida una búsqueda atorada más de 3 minutos' do
      lookup.update!(status: :running)
      travel 4.minutes do
        json = lookup.as_status_json
        expect(json[:status]).to eq('failed')
        expect(json[:error]).to include('tardó demasiado')
      end
    end

    it 'sólo expone el resultado cuando terminó' do
      lookup.update!(status: :running, result: { 'x' => 1 })
      expect(lookup.as_status_json[:result]).to be_nil
      lookup.update!(status: :done)
      expect(lookup.as_status_json[:result]).to eq('x' => 1)
    end
  end
  it 'acepta hasta 5 fotos y rechaza la sexta con un mensaje claro' do
    lookup = described_class.new(user: admin)
    5.times { attach(lookup, filename: 'a.png', content_type: 'image/png') }
    expect(lookup).to be_valid

    attach(lookup, filename: 'd.png', content_type: 'image/png')
    expect(lookup).not_to be_valid
    expect(lookup.errors.full_messages.join).to include('Máximo 5 fotos')
  end

  it 'rechaza pistas de más de 300 caracteres con un mensaje en español' do
    lookup = attach(described_class.new(user: admin, hints: 'x' * 301), filename: 'a.png', content_type: 'image/png')
    expect(lookup).not_to be_valid
    expect(lookup.errors.full_messages).to include('Las pistas no pueden pasar de 300 caracteres.')
  end

  it 'devuelve las fotos en el orden en que se subieron' do
    lookup = described_class.new(user: admin)
    attach(lookup, filename: 'frente.png', content_type: 'image/png')
    attach(lookup, filename: 'base.png', content_type: 'image/png')
    lookup.save!
    expect(lookup.reload.ordered_photos.map { |p| p.filename.to_s }).to eq(%w[frente.png base.png])
  end

  describe '.vision_monthly_cap_reached?' do
    def lookup_with_vision(used:, at: Time.current)
      travel_to(at) do
        attach(described_class.new(user: admin, vision_used: used), filename: 'a.png', content_type: 'image/png').tap(&:save!)
      end
    end

    before { stub_const('Collectibles::AiLookup::VISION_MONTHLY_CAP', 2) }

    it 'cuenta sólo las búsquedas de este mes que sí llamaron a Google' do
      lookup_with_vision(used: true)
      lookup_with_vision(used: false)
      lookup_with_vision(used: true, at: 2.months.ago)
      expect(described_class.vision_monthly_cap_reached?).to be(false)

      lookup_with_vision(used: true)
      expect(described_class.vision_monthly_cap_reached?).to be(true)
    end
  end
  describe 'tipos de foto' do
    def lookup_with(roles, count: roles.size)
      described_class.new(user: admin, photo_roles: roles).tap do |l|
        count.times { attach(l, filename: 'a.png', content_type: 'image/png') }
      end
    end

    it 'acepta tipos válidos que incluyen la vista 3/4' do
      expect(lookup_with(%w[base three_quarter package])).to be_valid
    end

    it 'sigue aceptando búsquedas sin tipos (página vieja)' do
      expect(lookup_with([], count: 2)).to be_valid
    end

    it 'exige la vista 3/4 cuando hay tipos' do
      lookup = lookup_with(%w[base side])
      expect(lookup).not_to be_valid
      expect(lookup.errors.full_messages).to include('Falta la vista 3/4 elevada.')
    end

    it 'rechaza tipos desconocidos, repetidos o que no cuadran con las fotos' do
      [lookup_with(%w[three_quarter selfie]), lookup_with(%w[three_quarter three_quarter]),
       lookup_with(%w[three_quarter], count: 2)].each do |lookup|
        expect(lookup).not_to be_valid
        expect(lookup.errors.full_messages).to include('Los tipos de foto no son válidos.')
      end
    end

    it 'empareja cada foto con su tipo en el orden de subida' do
      lookup = lookup_with(%w[three_quarter base]).tap(&:save!)
      expect(lookup.reload.labeled_photos.map(&:last)).to eq(%w[three_quarter base])
    end

    it 'sin tipos, cada foto queda con tipo nil' do
      lookup = lookup_with([], count: 2).tap(&:save!)
      expect(lookup.reload.labeled_photos.map(&:last)).to eq([nil, nil])
    end
  end
end
