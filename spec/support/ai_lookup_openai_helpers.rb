# frozen_string_literal: true

# Respuestas falsas de la Responses API de OpenAI para la búsqueda con IA.
# Ningún spec llama a OpenAI de verdad.
module AiLookupOpenaiHelpers
  def ai_lookup_answer(overrides = {})
    {
      'identification' => {
        'product_name' => 'Tomica No. 23 Nissan Skyline GT-R R34', 'brand' => 'Tomica',
        'series' => 'Tomica regular', 'model_code' => 'No. 23', 'scale' => '1/62',
        'year_or_edition' => '2019', 'confidence' => 0.86, 'notes' => 'Caja roja y blanca.'
      },
      'launch_date' => { 'value' => '2019-06', 'source_url' => 'https://www.hobbydb.com/marketplaces/1' },
      'rarity' => { 'level' => 'poco_comun', 'reasons' => ['Descontinuado en 2022'] },
      'prices_mx' => {
        'min' => 1, 'max' => 1, 'currency' => 'MXN',
        'listings' => [
          { 'title' => 'Tomica Skyline R34', 'price' => 349.0, 'price_original' => '$349 MXN',
            'url' => 'https://articulo.mercadolibre.com.mx/MLM-1', 'sold' => false },
          { 'title' => 'Tomica 23 GT-R', 'price' => 420.0, 'price_original' => '$420 MXN',
            'url' => 'https://www.amazon.com.mx/dp/B01', 'sold' => true }
        ]
      },
      'prices_world' => {
        'min' => 1, 'max' => 1, 'currency' => 'USD',
        'listings' => [
          { 'title' => 'Tomica #23 R34', 'price' => 8.9, 'price_original' => '¥1,320',
            'url' => 'https://www.hlj.com/tomica-23', 'sold' => false }
        ]
      },
      'suggested' => { 'category' => 'Autos a escala',
                       'description_es' => 'Réplica a escala 1/62 del Nissan Skyline GT-R R34 de la línea regular de Tomica.' },
      'warnings' => []
    }.merge(overrides)
  end

  def ai_lookup_openai_response(answer, searches: 3, input_tokens: 4000, output_tokens: 1200)
    {
      'output' => Array.new(searches) { { 'type' => 'web_search_call', 'status' => 'completed' } } + [
        { 'type' => 'message', 'content' => [{ 'type' => 'output_text', 'text' => answer.to_json, 'annotations' => [] }] }
      ],
      'usage' => { 'input_tokens' => input_tokens, 'output_tokens' => output_tokens }
    }
  end

  # Cliente falso: devuelve `response` (o ejecuta el bloque) y guarda los parámetros enviados.
  def stub_ai_lookup_openai(response = nil, &block)
    responses_api = double('OpenAI::Responses')
    sent = []
    allow(responses_api).to receive(:create) do |parameters:|
      sent << parameters
      block ? block.call(parameters) : response
    end
    allow(OpenAI::Client).to receive(:new).and_return(double('OpenAI::Client', responses: responses_api))
    sent
  end
end

RSpec.configure do |config|
  config.include AiLookupOpenaiHelpers
  # Aunque la máquina tenga GOOGLE_VISION_API_KEY, ningún spec llama a Google.
  config.before { allow(Collectibles::ReverseImageSearch).to receive(:api_key).and_return(nil) }
end
