# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::ReverseImageSearch do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) { Faraday.new { |builder| builder.adapter(:test, stubs) } }
  let(:jpeg) { 'jpeg-bytes' }
  let(:endpoint) { 'https://vision.googleapis.com/v1/images:annotate' }

  def vision_body(web_detection)
    { 'responses' => [{ 'webDetection' => web_detection }] }.to_json
  end

  def search(api_key: 'vision-test-key')
    described_class.new(jpeg, api_key: api_key, connection: connection)
  end

  it 'manda la imagen a Web Detection con la llave en el encabezado, nunca en la URL' do
    sent = nil
    sent_body = nil
    stubs.post(endpoint) do |env|
      sent = env
      sent_body = env.body # Faraday reemplaza env.body con la respuesta al terminar
      [200, { 'Content-Type' => 'application/json' }, vision_body({})]
    end
    search.call

    expect(sent.request_headers['X-Goog-Api-Key']).to eq('vision-test-key')
    expect(sent.url.to_s).not_to include('vision-test-key')
    body = JSON.parse(sent_body)
    expect(body.dig('requests', 0, 'image', 'content')).to eq(Base64.strict_encode64(jpeg))
    expect(body.dig('requests', 0, 'features')).to eq([{ 'type' => 'WEB_DETECTION', 'maxResults' => 10 }])
  end

  it 'regresa sugerencias recortadas y sólo páginas http(s)' do
    detection = {
      'bestGuessLabels' => Array.new(5) { |i| { 'label' => "guess #{i}" } },
      'webEntities' => [{ 'description' => 'Tomica', 'score' => 0.4 }, { 'score' => 0.9 }] +
                       Array.new(9) { |i| { 'description' => "e#{i}", 'score' => 0.1 + (i / 100.0) } },
      'pagesWithMatchingImages' => [{ 'url' => 'javascript:alert(1)', 'pageTitle' => 'mala' }] +
                                   Array.new(9) { |i| { 'url' => "https://x.example/#{i}", 'pageTitle' => "<b>P#{i}</b>#{'y' * 200}" } }
    }
    stubs.post(endpoint) { [200, { 'Content-Type' => 'application/json' }, vision_body(detection)] }
    result = search.call

    expect(result['best_guesses']).to eq(['guess 0', 'guess 1', 'guess 2'])
    expect(result['entities'].size).to eq(8)
    expect(result['entities'].first).to eq('description' => 'Tomica', 'score' => 0.4)
    expect(result['entities'].pluck('description')).not_to include(nil)
    expect(result['pages'].size).to eq(8)
    expect(result['pages'].pluck('url')).to all(start_with('https://'))
    expect(result['pages'].first['title'].length).to be <= 150
  end

  it 'regresa nil sin llamar a Google si no hay llave' do
    s = search(api_key: '')
    expect(s.call).to be_nil
    expect(s.called?).to be(false)
  end

  it 'regresa nil ante un 403 y registra el estado sin la llave' do
    logged = []
    allow(Rails.logger).to receive(:warn) { |message| logged << message }
    stubs.post(endpoint) do
      [403, { 'Content-Type' => 'application/json' }, { 'error' => { 'message' => 'Cloud Vision API has not been used in project 123' } }.to_json]
    end
    s = search

    expect(s.call).to be_nil
    expect(s.called?).to be(true)
    expect(logged.join).to include('403')
    expect(logged.join).not_to include('vision-test-key')
  end

  it 'regresa nil si Google responde con error dentro de la respuesta' do
    stubs.post(endpoint) { [200, { 'Content-Type' => 'application/json' }, { 'responses' => [{ 'error' => { 'message' => 'Bad image data.' } }] }.to_json] }
    expect(search.call).to be_nil
  end

  it 'regresa nil si Google no contesta a tiempo' do
    stubs.post(endpoint) { raise Faraday::TimeoutError, 'timeout' }
    s = search
    expect(s.call).to be_nil
    expect(s.called?).to be(true)
  end

  it 'regresa nil si Google no encontró nada útil' do
    stubs.post(endpoint) { [200, { 'Content-Type' => 'application/json' }, vision_body({})] }
    expect(search.call).to be_nil
  end
end
