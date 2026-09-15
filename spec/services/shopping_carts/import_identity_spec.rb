# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::ImportIdentity do
  let(:session_id) { SecureRandom.hex(16) }

  it 'is stable for the same browser session' do
    expect(described_class.new(session_id).digest).to eq(described_class.new(session_id).digest)
    expect(described_class.new(session_id).import_key).to eq(described_class.new(session_id).import_key)
  end

  it 'differs between independent browser sessions' do
    other = described_class.new(SecureRandom.hex(16))
    expect(described_class.new(session_id).digest).not_to eq(other.digest)
  end

  it 'requires a session id' do
    expect { described_class.new(nil) }.to raise_error(ArgumentError)
    expect { described_class.new('') }.to raise_error(ArgumentError)
  end

  it 'derives the key through a server-side key, never from the session id alone' do
    identity = described_class.new(session_id)

    expect(identity.import_key).not_to include(session_id)
    expect(identity.import_key).not_to eq(Digest::SHA256.hexdigest(session_id))
    expect(identity.digest).not_to eq(Digest::SHA256.hexdigest(session_id))
    expect(described_class.server_key.bytesize).to eq(32)
    expect(described_class.server_key).not_to eq(Rails.application.secret_key_base)
  end

  it 'persists only a digest that does not reveal the key' do
    identity = described_class.new(session_id)

    expect(identity.digest).to match(/\A\h{64}\z/)
    expect(identity.digest).not_to eq(identity.import_key)
    expect(identity.digest).to eq(Digest::SHA256.hexdigest("v1:#{identity.import_key}"))
  end

  it 'never leaks the key through inspect or to_s' do
    identity = described_class.new(session_id)

    expect(identity.inspect).not_to include(identity.import_key)
    expect(identity.to_s).not_to include(identity.import_key)
    expect(identity.inspect).not_to include(session_id)
  end
end
