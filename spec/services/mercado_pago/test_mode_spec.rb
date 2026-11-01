# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MercadoPago do
  around do |example|
    keys = %w[MERCADOPAGO_ACCESS_TOKEN MERCADOPAGO_TEST_MODE]
    saved = keys.index_with { |k| ENV.fetch(k, nil) }
    example.run
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  it 'is in test mode with TEST- credentials or the explicit flag, not with production ones' do
    ENV['MERCADOPAGO_ACCESS_TOKEN'] = 'TEST-123'
    ENV.delete('MERCADOPAGO_TEST_MODE')
    expect(described_class.test_mode?).to be(true)

    ENV['MERCADOPAGO_ACCESS_TOKEN'] = 'APP_USR-123'
    expect(described_class.test_mode?).to be(false)

    ENV['MERCADOPAGO_TEST_MODE'] = 'true'
    expect(described_class.test_mode?).to be(true)
  end
end
