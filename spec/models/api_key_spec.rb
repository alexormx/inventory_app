# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiKey, type: :model do
  let(:admin) { create(:user, :admin) }

  def generate(scopes: ApiKey::SCOPES)
    ApiKey.generate!(name: 'KataFrame', scopes: scopes, created_by: admin)
  end

  describe '.generate!' do
    it 'returns a pk_ token and stores only its digest and prefix' do
      key, token = generate

      expect(token).to start_with('pk_')
      expect(key.token_digest).to eq(ApiKey.digest(token))
      expect(key.token_prefix).to eq(token.first(11))
      expect(key.reload.attributes.values.map(&:to_s)).not_to include(token)
    end
  end

  describe '.authenticate' do
    it 'finds an active key by its token' do
      key, token = generate
      expect(ApiKey.authenticate(token)).to eq(key)
    end

    it 'returns nil once the key is revoked' do
      key, token = generate
      key.revoke!
      expect(key).to be_revoked
      expect(ApiKey.authenticate(token)).to be_nil
    end

    it 'returns nil for unknown, blank and legacy hex tokens' do
      generate
      ['pk_inexistente', '', nil, SecureRandom.hex(20)].each do |token|
        expect(ApiKey.authenticate(token)).to be_nil
      end
    end
  end

  describe 'validations' do
    it 'rejects unknown scopes' do
      expect(build(:api_key, scopes: ['orders:write'])).not_to be_valid
    end

    it 'requires at least one scope' do
      expect(build(:api_key, scopes: [])).not_to be_valid
    end

    it 'requires a name' do
      expect(build(:api_key, name: ' ')).not_to be_valid
    end
  end

  describe '#allows?' do
    it 'checks the granted scopes' do
      key = create(:api_key, scopes: ['products:read'])
      expect(key.allows?('products:read')).to be(true)
      expect(key.allows?('products:write')).to be(false)
    end
  end

  describe '#touch_last_used!' do
    it 'writes at most once per minute' do
      key = create(:api_key)
      travel_to(Time.zone.parse('2026-10-20 10:00:00')) { key.touch_last_used! }
      first = key.reload.last_used_at

      travel_to(Time.zone.parse('2026-10-20 10:00:30')) { key.touch_last_used! }
      expect(key.reload.last_used_at).to eq(first)

      travel_to(Time.zone.parse('2026-10-20 10:01:01')) { key.touch_last_used! }
      expect(key.reload.last_used_at).to be > first
    end
  end
end
