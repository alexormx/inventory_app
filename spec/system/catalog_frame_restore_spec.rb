# frozen_string_literal: true

require 'rails_helper'

# La rejilla del catálogo vive en un turbo-frame con data-turbo-action="advance",
# así que paginar empuja entradas de historial. Hay DOS fallos posibles y tiran
# en direcciones opuestas, por eso ambos están cubiertos aquí:
#
#   RESTAURACIÓN: Turbo cachea la instantánea de la página al salir de ella, y
#   esa captura compite con el reemplazo del frame. Si gana el frame, la entrada
#   de la página 1 queda guardada con la rejilla de la página 2 y el frame ya
#   `complete`. Al volver con Atrás, Turbo la reinstala y el frame, creyéndose
#   completo, nunca vuelve a pedir nada. No se recupera solo.
#
#   AVANCE: durante la paginación normal el frame llega a la página nueva ANTES
#   de que la visita actualice la URL. Secuencia real medida:
#     turbo:frame-render -> turbo:frame-load -> turbo:before-visit ->
#     turbo:visit(action="advance") -> turbo:before-render -> turbo:render -> turbo:load
#   Reparar ante ese desajuste transitorio devolvía la rejilla a la página
#   anterior y rompía la paginación en vivo (regresión vista en CI 33226136283).
#
# Por eso la reparación se condiciona a la señal semántica de Turbo: sólo una
# visita con action="restore" puede repararse.
#
#   MARCA PISADA: si la petición del frame lanzada al paginar sigue en vuelo
#   cuando el usuario pulsa Atrás, la respuesta tardía renderiza el frame
#   durante la restauración y Turbo sintetiza una visita "advance" (el frame
#   declara action="advance"). Esa visita llega entre el "restore" y el
#   turbo:load, y antes borraba la marca: el estado envenenado quedaba sin
#   reparar. Una visita normal sólo puede retirar la marca cuando la
#   restauración ya se resolvió.
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

  # Espera a que la navegación quede asentada antes de devolver el control: si
  # se navega otra vez antes de que Turbo empuje la entrada de historial, un
  # `go_back` posterior se salta el catálogo entero y aterriza en about:blank.
  def go_to_page_two
    within('turbo-frame#products_grid') do
      find('.catalog-pagination .page-link', text: '2', exact_text: true).click
    end
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 1)
    expect(page).to have_current_path(/page=2/, url: true)
  end

  # Deja el frame en el estado exacto que capturaron los artifacts de CI:
  # apuntando a otra página y marcado como completo.
  def poison_frame_to_page_two!
    page.execute_script(<<~JS)
      (() => {
        const f = document.getElementById('products_grid');
        f.setAttribute('src', location.pathname + location.search + '&page=2');
        f.setAttribute('complete', '');
      })()
    JS
  end

  def dispatch_visit(action)
    page.execute_script(
      "document.dispatchEvent(new CustomEvent('turbo:visit', { detail: { url: location.href, action: '#{action}' } }))"
    )
  end

  def dispatch_load
    page.execute_script("document.dispatchEvent(new Event('turbo:load'))")
  end

  # Turbo numera las entradas que crea. Un pushState hecho estando en una
  # entrada anterior NO cambia `history.length` —trunca lo que hubiera delante y
  # ocupa su sitio—, así que el índice es lo que delata el avance.
  def restoration_index
    page.evaluate_script('history.state && history.state.turbo ? history.state.turbo.restorationIndex : null')
  end

  # Deja el frame apuntando a otra página Y vacía la rejilla, para poder esperar
  # a que la respuesta de la reparación llegue de verdad: sin vaciarla, la
  # rejilla ya contiene lo que la reparación va a volver a pintar y no hay señal
  # observable de que la carga terminó.
  def poison_frame_and_empty_grid!
    page.execute_script(<<~JS)
      (() => {
        const f = document.getElementById('products_grid');
        f.setAttribute('src', location.pathname + location.search + '&page=99');
        f.setAttribute('complete', '');
        document.getElementById('product-grid-content').replaceChildren();
      })()
    JS
  end

  # ---------- 1 y 6: avance no debe repararse ----------

  it 'no revierte la rejilla al avanzar de la página 1 a la 2' do
    visit filtered_path
    accept_cookies_if_present
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)

    go_to_page_two

    aggregate_failures do
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 1)
      expect(page.current_url).to include('page=2')
      expect(frame_src_query).to include('page=2')
    end
  end

  it 'no corrige nada cuando frame y URL discrepan durante un avance' do
    visit filtered_path
    accept_cookies_if_present

    # Estado idéntico al de una restauración envenenada, pero la visita en curso
    # es un AVANCE: no debe tocarse.
    poison_frame_to_page_two!
    dispatch_visit('advance')
    dispatch_load

    aggregate_failures do
      expect(frame_src_query).to include('page=2')
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
    end
  end

  # ---------- 3: restauración envenenada sí se repara ----------

  it 'repara la rejilla cuando una restauración deja el frame en otra página' do
    visit filtered_path
    accept_cookies_if_present
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)

    poison_frame_to_page_two!
    expect(frame_src_query).to include('page=2')

    dispatch_visit('restore')
    dispatch_load

    aggregate_failures do
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
      expect(frame_src_query).not_to include('page=2')
      expect(page.current_url).not_to include('page=2')
    end
  end

  # ---------- 4: la marca de restauración sobrevive a una visita intercalada ----------

  # Regresión exacta observada en CI: la restauración quedó envenenada y la
  # reparación se saltó porque una respuesta de frame tardía sintetizó una
  # visita "advance" entre el "restore" y el turbo:load. Con la marca reasignada
  # en cada visita este ejemplo falla (la rejilla se queda en 1 tarjeta bajo la
  # URL de la página 1); la marca sólo puede retirarse si la restauración ya se
  # resolvió.
  it 'repara aunque una visita de avance se cuele durante la restauración' do
    visit filtered_path
    accept_cookies_if_present
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)

    poison_frame_to_page_two!
    dispatch_visit('restore')
    # Respuesta tardía del click de paginación renderizando dentro de la
    # restauración: el frame lleva data-turbo-action="advance", así que Turbo
    # propone una visita de avance antes de que llegue el turbo:load.
    dispatch_visit('advance')
    dispatch_load

    aggregate_failures do
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
      expect(frame_src_query).not_to include('page=2')
      expect(page.current_url).not_to include('page=2')
    end
  end

  # Una vez resuelta la restauración, un avance legítimo sí retira la marca: de
  # lo contrario la reparación seguiría armada y podría revertir la paginación.
  it 'deja de reparar cuando la restauración ya se resolvió y el usuario avanza' do
    visit filtered_path
    accept_cookies_if_present

    dispatch_visit('restore')
    dispatch_load

    poison_frame_to_page_two!
    dispatch_visit('advance')
    dispatch_load

    aggregate_failures do
      expect(frame_src_query).to include('page=2')
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
    end
  end

  # La reparación corrige la entrada actual; no navega. Si empujara historial
  # (pushState) truncaría las entradas hacia adelante y Adelante dejaría de
  # funcionar justo después de Atrás, que es la regresión que arregló #149.
  it 'no empuja historial al reparar, para no truncar el Adelante' do
    visit filtered_path
    accept_cookies_if_present
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)

    before_length = page.evaluate_script('history.length')

    poison_frame_to_page_two!
    dispatch_visit('restore')
    dispatch_load
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
    expect(frame_src_query).not_to include('page=2')

    expect(page.evaluate_script('history.length')).to eq(before_length)
  end

  # Turbo cachea la acción del frame cuando una navegación REAL la propone
  # (`delegate.action`, fijada en `proposeVisitIfNavigatedWithAction`) y NO
  # vuelve a leer `data-turbo-action` cuando el `src` cambia por atributo. Al
  # terminar CUALQUIER carga del frame llama a `changeHistory()` con esa acción
  # cacheada, así que la petición de la PROPIA reparación acababa haciendo
  # pushState: estando el usuario en la entrada anterior (tras Atrás) eso trunca
  # el Adelante, que es justo lo que #162 quería evitar. El intercambio del
  # atributo no lo impedía y `turbo:before-visit` tampoco, porque esa mutación
  # de historial no pasa por ninguna visita cancelable. Traza real del fallo:
  #
  #   history.pushState url=/catalog :: History.update << FrameController.changeHistory
  #                                     << #loadFrameResponse << loadResponse
  #   T6_before_forward  href=/catalog  restorationIndex=1  <- la entrada
  #                                     ordenada ya no existe; Adelante no mueve
  #
  # Aquí la navegación real de paginación deja esa acción cacheada y después se
  # fuerza la reparación: si vuelve a empujar, el índice avanza.
  it 'no avanza el historial cuando repara un frame que ya navegó de verdad' do
    visit filtered_path
    accept_cookies_if_present
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)

    # Navegación real del frame: aquí Turbo cachea action="advance".
    go_to_page_two

    before_length = page.evaluate_script('history.length')
    before_index = restoration_index
    before_url = page.current_url

    poison_frame_and_empty_grid!
    dispatch_visit('restore')
    dispatch_load

    # La respuesta de la reparación ya se pintó: la rejilla vuelve a la página 2.
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 1)

    aggregate_failures do
      expect(restoration_index).to eq(before_index)
      expect(page.evaluate_script('history.length')).to eq(before_length)
      expect(page.current_url).to eq(before_url)
    end
  end

  # ---------- 5: restauración sana no re-pide ----------

  it 'no re-pide nada cuando la restauración ya es coherente' do
    visit filtered_path
    accept_cookies_if_present
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)

    before_src = frame_src_query
    dispatch_visit('restore')
    dispatch_load

    aggregate_failures do
      expect(frame_src_query).to eq(before_src)
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
    end
  end

  # Nota: la navegación REAL de atrás/adelante la cubre
  # spec/system/catalog_filters_spec.rb:105. No se duplica aquí a propósito:
  # esa ruta sigue expuesta a una carrera residual de restauración (~2% medido),
  # y añadir un segundo ejemplo que la recorra sólo ampliaría esa exposición sin
  # aportar cobertura nueva. Lo que sí se fija aquí, de forma determinista, es la
  # lógica del módulo en ambas direcciones.

  # Requisito 8: ciclos repetidos no producen bucles ni re-peticiones en cadena.
  # Se ejercita con el ciclo de vida sintético a propósito: recorrer historial
  # real muchas veces es sensible a que el historial del navegador se acumula
  # ENTRE ejemplos (Capybara.reset_sessions! deja su propia entrada y no lo
  # limpia), y eso mediría esa fuga en vez de esta lógica.
  it 'no entra en bucle al repetir restauraciones' do
    visit filtered_path
    accept_cookies_if_present
    expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)

    3.times do
      poison_frame_to_page_two!
      dispatch_visit('restore')
      dispatch_load
      expect(page).to have_css('#product-grid-content .product-card-wrapper', count: 24)
    end

    aggregate_failures do
      expect(frame_src_query).not_to include('page=2')
      expect(page.current_url).not_to include('page=2')
    end
  end

end
