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

  def attach_slot(role, file = 'test1.png')
    attach_file "piece_photo_#{role}", Rails.root.join('spec/fixtures/files', file), make_visible: true
  end

  it 'empieza con cinco recuadros de fotos y sólo ofrece la IA con la vista 3/4' do
    visit admin_collectibles_quick_add_path

    headers = all('.card-header').map(&:text)
    expect(headers.first).to include('1. Fotos de la pieza (opcional)')
    expect(headers.index { |h| h.include?('2. Producto') }).to eq(1)
    %w[three_quarter base side top package].each do |role|
      expect(page).to have_css("[data-collectible-ai-lookup-target='slot'][data-role='#{role}']")
    end
    expect(page).to have_content('Vista 3/4 elevada').and have_content('Base / casting').and have_content('Empaque')
    expect(page).to have_field('piece_photo_extra', type: 'file')
    expect(page).to have_no_button('Identificar con IA')

    attach_slot('base')
    expect(page).to have_button('Identificar con IA', disabled: true)
    expect(page).to have_content('Agrega la vista 3/4 elevada para identificar con IA.')

    attach_slot('three_quarter')
    expect(page).to have_button('Identificar con IA', disabled: false)
    expect(page).to have_no_content('Agrega la vista 3/4 elevada')
  end

  it 'enseña la miniatura, avisa si falta la base y permite quitar la foto' do
    visit admin_collectibles_quick_add_path
    attach_slot('three_quarter')

    slot = find("[data-collectible-ai-lookup-target='slot'][data-role='three_quarter']")
    expect(slot).to have_css('img[data-slot-preview][src^="blob:"]', visible: :visible)
    expect(page).to have_content('Agrega la foto de la base para que la IA lea el casting.')

    within(slot) { click_button 'Quitar' }
    expect(slot).to have_no_css('img[data-slot-preview]', visible: :visible)
    expect(page).to have_no_button('Identificar con IA')
    expect(page.evaluate_script("document.getElementById('piece_photo_three_quarter').files.length")).to eq(0)
  end

  it 'al dar de alta guarda las fotos de los recuadros en orden en la pieza y en el producto nuevo' do
    Dir.mktmpdir do |dir|
      paths = { 'tres_cuartos.png' => 'red', 'base.png' => 'blue', 'extra.png' => 'green' }.to_h do |name, color|
        [name, File.join(dir, name).tap { |p| system('convert', '-size', '30x30', "xc:#{color}", p, exception: true) }]
      end
      visit admin_collectibles_quick_add_path
      fill_in 'product[product_name]', with: 'Pieza con recuadros'
      fill_in 'product[selling_price]', with: '250'
      attach_file 'piece_photo_base', paths['base.png'], make_visible: true
      attach_file 'piece_photo_three_quarter', paths['tres_cuartos.png'], make_visible: true
      attach_file 'piece_photo_extra', paths['extra.png']
      click_button 'Agregar Coleccionable'

      expect(page).to have_content('Coleccionable agregado', wait: 15)
      inventory = Inventory.order(:id).last
      expect(inventory.piece_images.attachments.sort_by(&:id).map { |a| a.filename.to_s })
        .to eq(%w[tres_cuartos.png base.png extra.png])
      expect(inventory.product.primary_product_image.filename.to_s).to eq('tres_cuartos.png')
    end
  end

  it 'llena sólo los campos vacíos y enseña rareza y precios por mercado' do
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    visit admin_collectibles_quick_add_path

    fill_in 'product[brand]', with: 'Mi marca'
    attach_slot('three_quarter')
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
    attach_slot('three_quarter')
    click_button 'Identificar con IA'

    expect(page).to have_button('Identificar con IA', disabled: true)
    gate << :go
    expect(page).to have_button('Identificar con IA', disabled: false, wait: 15)
    expect(Collectibles::AiLookup.count).to eq(1)
  end

  it 'enseña el error y permite reintentar' do
    stub_ai_lookup_openai { raise Collectibles::AiLookupService::Error, 'Respuesta vacía de OpenAI' }
    visit admin_collectibles_quick_add_path
    attach_slot('three_quarter')
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
    attach_slot('three_quarter')
    attach_slot('base', 'test2.png')
    fill_in 'Pistas (opcional)', with: 'Base: Tomica No. 23'
    click_button 'Identificar con IA'

    panel = '[data-collectible-ai-lookup-target="panel"]'
    expect(page).to have_css(panel, text: 'No estoy seguro', wait: 15)
    expect(find_field('product[product_name]').value).to be_blank
    within(panel) { expect(page).to have_content('Google sugiere: tomica skyline gt-r') }

    lookup = Collectibles::AiLookup.last
    expect(lookup.photos.count).to eq(2)
    expect(lookup.photo_roles).to eq(%w[three_quarter base])
    expect(lookup.hints).to eq('Base: Tomica No. 23')

    within(panel) { all(:button, 'Es esta')[1].click }
    expect(find_field('product[product_name]').value).to eq('Tomica Premium 08 Nissan Skyline GT-R V-spec')
    expect(find_field('product[brand]').value).to eq('Tomica Premium')
    # La descripción se escribió para el primer candidato: no se usa para otro.
    expect(find_field('product[description]').value).to be_blank
  end

  it 'Enter en las pistas inicia la búsqueda y no da de alta el producto' do
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    visit admin_collectibles_quick_add_path
    fill_in 'product[product_name]', with: 'Ya escrito'
    attach_slot('three_quarter')

    expect do
      find_field('Pistas (opcional)').send_keys('Base: Tomica 23', :enter)
      expect(page).to have_css('[data-collectible-ai-lookup-target="panel"]', text: 'Resultado de la IA', wait: 15)
    end.not_to change(Product, :count)
    expect(page).to have_current_path(admin_collectibles_quick_add_path)
    expect(Collectibles::AiLookup.last.hints).to eq('Base: Tomica 23')
  end
end
