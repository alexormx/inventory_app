# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MercadoPago::WebhookSignature do
  let(:secret) { 'test-webhook-secret' }
  let(:ts) { '1704908010' }

  def header_for(data_id:, request_id:, secret_key: secret)
    manifest = "id:#{data_id};request-id:#{request_id};ts:#{ts};"
    "ts=#{ts},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret_key, manifest)}"
  end

  it 'accepts a signature built from data.id, x-request-id and ts' do
    header = header_for(data_id: '123456', request_id: 'req-1')

    expect(described_class.valid?(signature_header: header, request_id: 'req-1', data_id: '123456', secret: secret)).to be(true)
  end

  it 'lower-cases alphanumeric ids before signing, as Mercado Pago does' do
    header = header_for(data_id: 'abc123', request_id: 'req-1')

    expect(described_class.valid?(signature_header: header, request_id: 'req-1', data_id: 'ABC123', secret: secret)).to be(true)
  end

  it 'rejects a tampered id, a wrong secret, a missing header or a missing secret' do
    header = header_for(data_id: '123456', request_id: 'req-1')

    expect(described_class.valid?(signature_header: header, request_id: 'req-1', data_id: '999', secret: secret)).to be(false)
    expect(described_class.valid?(signature_header: header_for(data_id: '123456', request_id: 'req-1', secret_key: 'otra'),
                                  request_id: 'req-1', data_id: '123456', secret: secret)).to be(false)
    expect(described_class.valid?(signature_header: '', request_id: 'req-1', data_id: '123456', secret: secret)).to be(false)
    expect(described_class.valid?(signature_header: header, request_id: 'req-1', data_id: '123456', secret: nil)).to be(false)
  end
end
