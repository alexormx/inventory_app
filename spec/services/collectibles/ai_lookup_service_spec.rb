# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookupService do
  let(:admin) { create(:user, :admin) }
  let(:lookup) do
    Collectibles::AiLookup.new(user: admin).tap do |l|
      l.photos.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
      l.save!
    end
  end

  before { allow(OpenAI.configuration).to receive(:access_token).and_return('test-key') }

  it 'manda una sola llamada con imagen, búsqueda abierta y esquema estricto' do
    sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
    described_class.new(lookup).call

    expect(sent.size).to eq(1)
    params = sent.first
    expect(params[:model]).to eq('gpt-4.1')
    # Para identificar busca en toda la web; los precios se filtran en el servidor.
    expect(params[:tools]).to eq([{ type: 'web_search' }])
    # Le dice a la IA qué suele ser cada foto, en el orden que pide la pantalla.
    expect(params[:instructions]).to include('1) vista 3/4 elevada').and include('2) la base')
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

  it 'descarta un precio mundial que se quedó en yenes y lo avisa' do
    answer = ai_lookup_answer
    answer['prices_world']['listings'] << { 'title' => 'Sin convertir', 'price' => 1320.0, 'price_original' => '¥1,320',
                                            'url' => 'https://www.amazon.co.jp/dp/X', 'sold' => false }
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    data = described_class.new(lookup).call.data

    expect(data['prices_world']['listings'].map { |l| l['price'] }).to eq([8.9])
    expect(data['prices_world']['max']).to eq(8.9)
    expect(data['warnings'].join).to include('yenes')
  end

  it 'limita a 5 enlaces por mercado' do
    answer = ai_lookup_answer
    answer['prices_world']['listings'] = Array.new(8) do |i|
      { 'title' => "L#{i}", 'price' => 10.0 + i, 'price_original' => '$', 'url' => "https://www.ebay.com/itm/#{i}", 'sold' => true }
    end
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    expect(described_class.new(lookup).call.data['prices_world']['listings'].size).to eq(5)
  end

  it 'conserva la fuente de la fecha de cualquier sitio http(s), sin aviso' do
    answer = ai_lookup_answer('launch_date' => { 'value' => '2019', 'source_url' => 'https://www.takaratomy.co.jp/products/tomica/23' })
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    data = described_class.new(lookup).call.data

    expect(data['launch_date']['source_url']).to eq('https://www.takaratomy.co.jp/products/tomica/23')
    expect(data['warnings'].join).not_to include('fecha de lanzamiento')
  end

  it 'tira una fuente de fecha que no es http(s)' do
    answer = ai_lookup_answer('launch_date' => { 'value' => '2019', 'source_url' => 'javascript:alert(1)' })
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    expect(described_class.new(lookup).call.data['launch_date']['source_url']).to be_nil
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
    fake = Collectibles::AiLookup.new(user: admin).tap do |l|
      l.photos.attach(io: StringIO.new('hola, no soy imagen'), filename: 'falsa.png', content_type: 'image/png')
      l.save!
    end
    sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))

    expect { described_class.new(fake).call }.to raise_error(described_class::Error, /no es una imagen válida/)
    expect(sent).to be_empty
  end

  it 'reduce cada foto a 1024 px y le quita los metadatos antes de mandarla' do
    big = Tempfile.new(['big', '.jpg'])
    system('convert', '-size', '3000x2000', 'xc:red', '-set', 'comment', 'GPS 19.43,-99.13', big.path, exception: true)
    lookup.photos.attach(io: File.open(big.path), filename: 'big.jpg', content_type: 'image/jpeg')

    sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
    described_class.new(lookup).call

    images = sent.first[:input].first[:content].select { |c| c[:type] == 'input_image' }
    expect(images.size).to eq(2)
    images.each do |img|
      image = MiniMagick::Image.read(Base64.strict_decode64(img[:image_url].delete_prefix('data:image/jpeg;base64,')))
      expect([image.width, image.height].max).to be <= 1024
      expect(image['%c'].to_s).not_to include('GPS')
    end
  ensure
    big&.close!
  end

  describe 'fotos, pistas y búsqueda inversa' do
    def user_text(sent)
      sent.first[:input].first[:content].find { |c| c[:type] == 'input_text' }[:text]
    end

    def stub_reverse_search(result, called: true)
      search = instance_double(Collectibles::ReverseImageSearch, call: result, called?: called)
      allow(Collectibles::ReverseImageSearch).to receive(:new).and_return(search)
      search
    end

    let(:google) { { 'best_guesses' => ['tomica skyline gt-r r34'], 'entities' => [], 'pages' => [] } }

    it 'manda las fotos en el orden en que se subieron' do
      lookup.photos.attach(io: File.open(Rails.root.join('spec/fixtures/files/test2.png')), filename: 'base.png', content_type: 'image/png')
      lookup.save!
      sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
      described_class.new(lookup.reload).call

      expect(sent.first[:input].first[:content].count { |c| c[:type] == 'input_image' }).to eq(2)
    end

    it 'incluye las pistas del admin en el mensaje' do
      lookup.update!(hints: 'Base: Tomica No. 23, made in Vietnam')
      sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
      described_class.new(lookup).call

      expect(user_text(sent)).to include('Pistas del admin').and include('Base: Tomica No. 23, made in Vietnam')
    end

    it 'pasa lo que sugiere Google, lo guarda en el resultado y marca el uso' do
      stub_reverse_search(google)
      sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
      data = described_class.new(lookup).call.data

      expect(user_text(sent)).to include('Búsqueda inversa de Google').and include('tomica skyline gt-r r34')
      expect(data['reverse_image']).to eq(google)
      expect(lookup.reload.vision_used).to be(true)
    end

    it 'cuenta el uso de Google aunque OpenAI falle después' do
      stub_reverse_search(google)
      stub_ai_lookup_openai { raise Collectibles::AiLookupService::Error, 'Respuesta vacía de OpenAI' }

      expect { described_class.new(lookup).call }.to raise_error(described_class::Error)
      expect(lookup.reload.vision_used).to be(true)
    end

    it 'sigue sin Google si Google no dio nada, pero cuenta la llamada' do
      stub_reverse_search(nil, called: true)
      sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
      data = described_class.new(lookup).call.data

      expect(sent.size).to eq(1)
      expect(user_text(sent)).not_to include('Búsqueda inversa')
      expect(data['reverse_image']).to be_nil
      expect(lookup.reload.vision_used).to be(true)
    end

    it 'no llama a Google al llegar al tope del mes' do
      allow(Collectibles::AiLookup).to receive(:vision_monthly_cap_reached?).and_return(true)
      expect(Collectibles::ReverseImageSearch).not_to receive(:new)
      stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))

      described_class.new(lookup).call
      expect(lookup.reload.vision_used).to be(false)
    end

    it 'no marca uso de Google si no hay llave configurada' do
      stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
      described_class.new(lookup).call
      expect(lookup.reload.vision_used).to be(false)
    end

    it 'en un reintento reusa lo que dio Google en vez de volver a llamarlo' do
      lookup.update_columns(vision_used: true, result: { 'reverse_image' => google })
      expect(Collectibles::ReverseImageSearch).not_to receive(:new)
      sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
      data = described_class.new(lookup).call.data

      expect(user_text(sent)).to include('tomica skyline gt-r r34')
      expect(data['reverse_image']).to eq(google)
    end

    it 'guarda lo que dio Google en cuanto llega, para que un reintento lo reuse' do
      stub_reverse_search(google)
      stub_ai_lookup_openai { raise Collectibles::AiLookupService::RateLimitError, '429' }

      expect { described_class.new(lookup).call }.to raise_error(described_class::RateLimitError)
      expect(lookup.reload.result).to eq('reverse_image' => google)
    end

    it 'deja a lo más 3 candidatos' do
      answer = ai_lookup_answer
      answer['candidates'] = Array.new(5) do |i|
        { 'product_name' => "C#{i}", 'brand' => nil, 'model_code' => nil, 'reason' => 'r', 'confidence' => 0.1 }
      end
      stub_ai_lookup_openai(ai_lookup_openai_response(answer))
      expect(described_class.new(lookup).call.data['candidates'].pluck('product_name')).to eq(%w[C0 C1 C2])
    end
  end
end
