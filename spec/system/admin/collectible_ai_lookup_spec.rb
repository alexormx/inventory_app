# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin identifica un coleccionable con IA', type: :system do
  let(:admin) { create(:user, :admin) }

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  before do
    driven_by :selenium_chrome_headless
    sign_in admin
    allow(OpenAI.configuration).to receive(:access_token).and_return('test-key')
  end

  def answer
    ai_lookup_answer.tap do |a|
      a['prices_world']['listings'].first['title'] = '<img src=x onerror="window.pwned=1">Tomica #23'
    end
  end

  it 'empieza con las fotos y sólo ofrece la IA cuando hay una foto' do
    visit admin_collectibles_quick_add_path

    headers = all('.card-header').map(&:text)
    expect(headers.first).to include('1. Fotos de la pieza (opcional)')
    expect(headers.index { |h| h.include?('2. Producto') }).to eq(1)
    expect(page).to have_no_button('Identificar con IA')

    attach_file 'inventory[piece_images][]', Rails.root.join('spec/fixtures/files/test1.png')
    expect(page).to have_button('Identificar con IA', disabled: false)
  end

  it 'llena sólo los campos vacíos y enseña rareza y precios por mercado' do
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    visit admin_collectibles_quick_add_path

    fill_in 'product[brand]', with: 'Mi marca'
    attach_file 'inventory[piece_images][]', Rails.root.join('spec/fixtures/files/test1.png')
    click_button 'Identificar con IA'

    expect(page).to have_css('[data-collectible-ai-lookup-target="panel"]', text: 'Poco común', wait: 15)
    expect(find_field('product[product_name]').value).to eq('Tomica No. 23 Nissan Skyline GT-R R34')
    expect(find_field('product[category]').value).to eq('Autos a escala')
    expect(find_field('product[description]').value).to include('escala 1/62')
    # Lo que el admin ya escribió no se toca; la sugerencia queda en el panel.
    expect(find_field('product[brand]').value).to eq('Mi marca')
    within('[data-collectible-ai-lookup-target="panel"]') do
      expect(page).to have_button('Usar', count: 1)
      expect(page).to have_content('MXN $349 – $420')
      expect(page).to have_content('USD $8.90 – $8.90')
      expect(page).to have_content('¥1,320')
      expect(page).to have_content('<img src=x onerror="window.pwned=1">Tomica #23')
      expect(page).to have_link(href: 'https://articulo.mercadolibre.com.mx/MLM-1')
    end
    expect(page.evaluate_script('window.pwned')).to be_nil
    # Precio y SKU nunca se llenan solos.
    expect(find_field('product[selling_price]').value).to be_blank
    expect(find_field('product[product_sku]').value).to be_blank

    click_button 'Usar'
    expect(find_field('product[brand]').value).to eq('Tomica')
  end

  it 'deshabilita el botón mientras busca' do
    gate = Queue.new
    stub_ai_lookup_openai do
      gate.pop # retiene la respuesta hasta que el spec revise el botón
      ai_lookup_openai_response(answer)
    end
    visit admin_collectibles_quick_add_path
    attach_file 'inventory[piece_images][]', Rails.root.join('spec/fixtures/files/test1.png')
    click_button 'Identificar con IA'

    expect(page).to have_button('Identificar con IA', disabled: true)
    gate << :go
    expect(page).to have_button('Identificar con IA', disabled: false, wait: 15)
    expect(Collectibles::AiLookup.count).to eq(1)
  end

  it 'enseña el error y permite reintentar' do
    stub_ai_lookup_openai { raise Collectibles::AiLookupService::Error, 'Respuesta vacía de OpenAI' }
    visit admin_collectibles_quick_add_path
    attach_file 'inventory[piece_images][]', Rails.root.join('spec/fixtures/files/test1.png')
    click_button 'Identificar con IA'

    expect(page).to have_content('Respuesta vacía de OpenAI', wait: 15)
    expect(page).to have_button('Reintentar')
  end

  it 'si la IA no está segura no llena nada y deja elegir entre candidatos' do
    unsure = ai_lookup_answer.tap { |a| a['identification']['confidence'] = 0.45 }
    stub_ai_lookup_openai(ai_lookup_openai_response(unsure))
    allow(Collectibles::ReverseImageSearch).to receive(:new).and_return(
      instance_double(Collectibles::ReverseImageSearch,
                      call: { 'best_guesses' => ['tomica skyline gt-r'], 'entities' => [], 'pages' => [] }, called?: true)
    )
    visit admin_collectibles_quick_add_path
    attach_file 'inventory[piece_images][]', [Rails.root.join('spec/fixtures/files/test1.png'), Rails.root.join('spec/fixtures/files/test2.png')]
    fill_in 'Pistas (opcional)', with: 'Base: Tomica No. 23'
    click_button 'Identificar con IA'

    panel = '[data-collectible-ai-lookup-target="panel"]'
    expect(page).to have_css(panel, text: 'No estoy seguro', wait: 15)
    expect(find_field('product[product_name]').value).to be_blank
    within(panel) { expect(page).to have_content('Google sugiere: tomica skyline gt-r') }

    lookup = Collectibles::AiLookup.last
    expect(lookup.photos.count).to eq(2)
    expect(lookup.hints).to eq('Base: Tomica No. 23')

    within(panel) { all(:button, 'Es esta')[1].click }
    expect(find_field('product[product_name]').value).to eq('Tomica Premium 08 Nissan Skyline GT-R V-spec')
    expect(find_field('product[brand]').value).to eq('Tomica Premium')
    # La descripción se escribió para el primer candidato: no se usa para otro.
    expect(find_field('product[description]').value).to be_blank
  end

  it 'avisa que sólo manda las primeras 3 fotos' do
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    Dir.mktmpdir do |dir|
      files = Array.new(4) do |i|
        File.join(dir, "foto#{i}.png").tap { |path| system('convert', '-size', '20x20', 'xc:blue', path, exception: true) }
      end
      visit admin_collectibles_quick_add_path
      attach_file 'inventory[piece_images][]', files

      expect(page).to have_content('Se enviarán a la IA las primeras 3 de 4 fotos.')
      click_button 'Identificar con IA'
      expect(page).to have_css('[data-collectible-ai-lookup-target="panel"]', text: 'Resultado de la IA', wait: 15)
      expect(Collectibles::AiLookup.last.photos.count).to eq(3)
    end
  end
end
