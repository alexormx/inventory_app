# frozen_string_literal: true

require 'rails_helper'

# La rejilla del catálogo vive en un turbo-frame con data-turbo-action="advance",
# así que paginar empuja entradas de historial. Turbo captura la instantánea de
# la página al navegar fuera de ella, y esa captura compite con el reemplazo del
# frame: cuando gana el frame, la entrada de la página 1 queda guardada con el
# contenido de la página 2 y con el frame ya marcado `complete`. Al volver con
# Atrás, Turbo reinstala esa instantánea y el frame, creyéndose completo, nunca
# vuelve a pedir nada.
#
# El síntoma es una página incoherente: la URL dice página 1 y la rejilla enseña
# la 2. Reproducido en local ~7% de las veces, y verificado que NO se recupera
# solo (seguía mal a los 25 s), así que no era lentitud.
#
# La invariante es que el `src` del frame concuerde con la consulta de la URL.
# Aquí se envenena el frame a propósito para probar la reconciliación de forma
# determinista, en vez de depender de ganar la carrera.
RSpec.describe 'Catalog frame restoration', :js, type: :system do
  before { driven_by :selenium_chrome_headless }

  let(:filtered_path) do
    catalog_path(q: 'Sample', categories: ['Autos'], brands: ['Tomica'],
                 series: ['Vintage'], to_order: '1', sort: 'name_asc')
  end

  before do
    create_list(:product, 25, skip_seed_inventory: true, category: 'Autos',
                              brand: 'Tomica', series: 'Vintage', backorder_allowed: true)
  end

  def frame_src_query
    page.evaluate_script(<<~JS)
      (() => {
        const f = document.getElementById('products_grid');
        const src = f && f.getAttribute('src');
        return src ? new URL(src, location.href).search : '';
      })()
    JS
  end

  it 'refetches the grid when a restored frame disagrees with the URL' do
    visit filtered_path
    accept_cookies_if_present
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)

    # Estado exacto que capturó el artifact de CI: el frame quedó apuntando a la
    # página 2 y marcado como completo, mientras la URL sigue en la página 1.
    page.execute_script(<<~JS)
      (() => {
        const f = document.getElementById('products_grid');
        f.setAttribute('src', location.pathname + location.search + '&page=2');
        f.setAttribute('complete', '');
      })()
    JS
    expect(frame_src_query).to include('page=2')

    # turbo:load es lo que dispara Turbo al terminar una restauración.
    page.execute_script("document.dispatchEvent(new Event('turbo:load'))")

    aggregate_failures do
      # La rejilla vuelve a lo que corresponde a la URL, no a lo que quedó cacheado.
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
      expect(frame_src_query).not_to include('page=2')
      expect(page.current_url).not_to include('page=2')
    end
  end

  it 'leaves a frame alone when it already agrees with the URL' do
    visit filtered_path
    accept_cookies_if_present
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)

    before_src = frame_src_query
    page.execute_script("document.dispatchEvent(new Event('turbo:load'))")

    aggregate_failures do
      expect(frame_src_query).to eq(before_src)
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
    end
  end

  it 'still restores the correct page after real back navigation' do
    visit filtered_path
    accept_cookies_if_present
    within('turbo-frame#products_grid') do
      find('.catalog-pagination .page-link', text: '2', exact_text: true).click
    end
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 1)

    page.go_back

    aggregate_failures do
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
      expect(page.current_url).not_to include('page=2')
    end
  end
end
