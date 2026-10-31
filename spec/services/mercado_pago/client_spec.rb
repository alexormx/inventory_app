# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MercadoPago::Client do
  subject(:client) { described_class.new(access_token: 'TEST-abc') }

  let(:http) { instance_double(Net::HTTP) }
  let(:sent) { [] }

  def respond_with(klass, code, body)
    response = klass.new('1.1', code, 'msg')
    allow(response).to receive(:body).and_return(body.to_json)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request) { |req| sent << req; response } # rubocop:disable Style/Semicolon
  end

  it 'sends the bearer token, JSON body and idempotency key when creating a preference' do
    respond_with(Net::HTTPCreated, '201', { id: 'pref-1', init_point: 'https://mp/redirect' })

    result = client.create_preference({ items: [] }, idempotency_key: 'k-1')

    expect(result['id']).to eq('pref-1')
    req = sent.first
    expect(req.path).to eq('/checkout/preferences')
    expect(req['Authorization']).to eq('Bearer TEST-abc')
    expect(req['X-Idempotency-Key']).to eq('k-1')
    expect(JSON.parse(req.body)).to eq('items' => [])
  end

  it 'raises a MercadoPago::Error without leaking the token on API errors' do
    respond_with(Net::HTTPUnauthorized, '401', { message: 'invalid access token' })

    expect { client.payment('123') }.to raise_error(MercadoPago::Error) { |e|
      expect(e.message).to include('401', 'invalid access token')
      expect(e.message).not_to include('TEST-abc')
    }
  end

  it 'refuses non-numeric payment ids before calling the API' do
    expect { client.payment('../users') }.to raise_error(MercadoPago::Error)
  end

  it 'requires an access token' do
    expect { described_class.new(access_token: nil) }.to raise_error(MercadoPago::Error)
  end
end
