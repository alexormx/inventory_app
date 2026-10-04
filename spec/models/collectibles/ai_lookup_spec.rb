# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookup do
  let(:admin) { create(:user, :admin) }

  def attach(lookup, filename:, content_type:, io: File.open(Rails.root.join('spec/fixtures/files/test1.png')))
    lookup.photo.attach(io: io, filename: filename, content_type: content_type)
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
end
