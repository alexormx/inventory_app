# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookupService do
  let(:admin) { create(:user, :admin) }
  let(:lookup) do
    Collectibles::AiLookup.new(user: admin).tap do |l|
      l.photo.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
      l.save!
    end
  end

  before { allow(OpenAI.configuration).to receive(:access_token).and_return('test-key') }

  it 'manda una sola llamada con imagen, búsqueda restringida y esquema estricto' do
    sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
    described_class.new(lookup).call

    expect(sent.size).to eq(1)
    params = sent.first
    expect(params[:model]).to eq('gpt-4.1')
    expect(params[:tools]).to eq([{ type: 'web_search', filters: { allowed_domains: Collectibles::AiLookupSources::ALL } }])
    expect(params.dig(:text, :format, :type)).to eq('json_schema')
    expect(params.dig(:text, :format, :strict)).to be(true)
    image = params[:input].first[:content].find { |c| c[:type] == 'input_image' }
    expect(image[:image_url]).to start_with('data:image/jpeg;base64,')
  end

  it 'devuelve el resultado, tokens, búsquedas y costo' do
    stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer, searches: 4, input_tokens: 5000, output_tokens: 1000))
    result = described_class.new(lookup).call

    expect(result.data.dig('identification', 'brand')).to eq('Tomica')
    expect(result.tokens_input).to eq(5000)
    expect(result.tokens_output).to eq(1000)
    expect(result.web_search_calls).to eq(4)
    # 5000*2/1M + 1000*8/1M + 4*25/1000 = 0.01 + 0.008 + 0.1 = 0.118 USD → 12 centavos
    expect(result.cost_cents).to eq(12)
  end

  it 'recalcula el rango con los enlaces que sobreviven y conserva el precio original' do
    stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
    data = described_class.new(lookup).call.data

    expect(data['prices_mx'].slice('min', 'max')).to eq('min' => 349.0, 'max' => 420.0)
    expect(data['prices_mx']['currency']).to eq('MXN')
    expect(data.dig('prices_world', 'listings', 0, 'price_original')).to eq('¥1,320')
    expect(data['prices_world']['currency']).to eq('USD')
  end

  it 'tira enlaces fuera de la lista o del mercado equivocado' do
    answer = ai_lookup_answer
    answer['prices_mx']['listings'] << { 'title' => 'Fake', 'price' => 10.0, 'price_original' => '$10',
                                         'url' => 'https://scam.example/x', 'sold' => true }
    answer['prices_world']['listings'] << { 'title' => 'MX en mundial', 'price' => 5.0, 'price_original' => '$5',
                                            'url' => 'https://www.amazon.com.mx/dp/Z', 'sold' => false }
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    data = described_class.new(lookup).call.data

    expect(data['prices_mx']['listings'].map { |l| l['url'] }).not_to include('https://scam.example/x')
    expect(data['prices_mx']['min']).to eq(349.0)
    expect(data['prices_world']['listings'].size).to eq(1)
  end

  it 'deja en null un mercado sin enlaces confiables' do
    answer = ai_lookup_answer
    answer['prices_mx']['listings'] = [{ 'title' => 'x', 'price' => 1.0, 'price_original' => '$1',
                                         'url' => 'https://example.com/x', 'sold' => false }]
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    expect(described_class.new(lookup).call.data['prices_mx']).to be_nil
  end

  it 'limita a 5 enlaces por mercado' do
    answer = ai_lookup_answer
    answer['prices_world']['listings'] = Array.new(8) do |i|
      { 'title' => "L#{i}", 'price' => 10.0 + i, 'price_original' => '$', 'url' => "https://www.ebay.com/itm/#{i}", 'sold' => true }
    end
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    expect(described_class.new(lookup).call.data['prices_world']['listings'].size).to eq(5)
  end

  it 'quita la fuente de la fecha si no es confiable y lo avisa' do
    answer = ai_lookup_answer('launch_date' => { 'value' => '2019', 'source_url' => 'https://blog.example/x' })
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    data = described_class.new(lookup).call.data

    expect(data['launch_date']).to eq('value' => '2019', 'source_url' => nil)
    expect(data['warnings'].join).to include('fecha de lanzamiento')
  end

  it 'falla con un error legible ante JSON roto' do
    response = ai_lookup_openai_response(ai_lookup_answer)
    response['output'].last['content'].first['text'] = '{"identification": '
    stub_ai_lookup_openai(response)
    expect { described_class.new(lookup).call }.to raise_error(described_class::Error, /Respuesta inválida/)
  end

  it 'falla si OpenAI rechaza la solicitud' do
    stub_ai_lookup_openai('output' => [{ 'type' => 'message', 'content' => [{ 'type' => 'refusal', 'refusal' => 'no' }] }],
                          'usage' => {})
    expect { described_class.new(lookup).call }.to raise_error(described_class::Error, /rechazó/)
  end

  it 'convierte el 429 en RateLimitError' do
    stub_ai_lookup_openai { raise Faraday::TooManyRequestsError, 'the server responded with status 429' }
    expect { described_class.new(lookup).call }.to raise_error(described_class::RateLimitError)
  end

  it 'falla claro si no hay llave configurada' do
    allow(OpenAI.configuration).to receive(:access_token).and_return(nil)
    expect { described_class.new(lookup).call }.to raise_error(described_class::NotConfiguredError, /no está configurado/)
  end

  it 'no llama a OpenAI si el archivo no es una imagen legible' do
    lookup.photo.attach(io: StringIO.new('hola, no soy imagen'), filename: 'falsa.png', content_type: 'image/png')
    sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))

    expect { described_class.new(lookup).call }.to raise_error(described_class::Error, /no es una imagen válida/)
    expect(sent).to be_empty
  end

  it 'reduce la foto a 1024 px y le quita los metadatos antes de mandarla' do
    big = Tempfile.new(['big', '.jpg'])
    system('convert', '-size', '3000x2000', 'xc:red', '-set', 'comment', 'GPS 19.43,-99.13', big.path, exception: true)
    lookup.photo.attach(io: File.open(big.path), filename: 'big.jpg', content_type: 'image/jpeg')

    sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
    described_class.new(lookup).call

    data_url = sent.first[:input].first[:content].find { |c| c[:type] == 'input_image' }[:image_url]
    jpeg = Base64.strict_decode64(data_url.delete_prefix('data:image/jpeg;base64,'))
    image = MiniMagick::Image.read(jpeg)
    expect([image.width, image.height].max).to be <= 1024
    expect(image['%c'].to_s).not_to include('GPS')
  ensure
    big&.close!
  end
end
