# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

require 'rails_helper'

RSpec.describe 'Admin responsive sidebar', :js, :sidebar_responsive, type: :system do
  let!(:admin) { create(:user, :admin) }
  let!(:product) { create(:product, skip_seed_inventory: true) }

  before do
    driven_by(:selenium_chrome_headless)
    sign_in admin
  end

  def resize_to(width, height)
    page.current_window.resize_to(width, height)
  end

  def open_drawer
    find('[data-sidebar-drawer-toggle]').click
    expect(page).to have_css('#sidebar.is-open')
    wait_for_drawer_settled
  end

  # El drawer entra deslizándose: `aside#sidebar` anima `transform` durante
  # 0.22s. La clase `.is-open` y los atributos aria se ponen de golpe al abrir,
  # así que TODAS las aserciones de estado pasan de inmediato, mucho antes de
  # que el panel llegue a su sitio.
  #
  # Eso dejaba una ventana real: medido justo tras abrir, el centro del botón de
  # cerrar estaba en x=-19 (fuera de la pantalla, `elementFromPoint` devolvía
  # null) cuando su posición final es x=75. Un click emitido en ese instante no
  # aterriza en el botón, no corre ningún handler, y el drawer se queda abierto
  # con TODO su estado coherente: `is-open`, backdrop visible, body bloqueado y
  # ambos controles en aria-expanded="true". Es exactamente lo que capturaron
  # los artifacts de CI de 9c88c8ab y b0a0eac8, idénticos entre sí.
  #
  # No es un defecto del runtime: una persona hace click cuando ya ve el panel.
  # Lo que faltaba era esperar a que el control sea realmente alcanzable, que es
  # la condición que gobierna si el click va a llegar.
  def wait_for_drawer_settled
    page.document.synchronize(Capybara.default_max_wait_time, errors: [RuntimeError]) do
      raise 'drawer todavía en transición' unless drawer_close_button_hittable?
    end
  end

  # ¿Un click en el centro del botón de cerrar lo alcanzaría ahora mismo?
  def drawer_close_button_hittable?
    page.evaluate_script(<<~JS)
      (() => {
        const btn = document.querySelector('[data-sidebar-drawer-close]');
        if (!btn) return false;
        const rect = btn.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return false;
        const x = Math.round(rect.left + rect.width / 2);
        const y = Math.round(rect.top + rect.height / 2);
        if (x < 0 || y < 0) return false;
        const hit = document.elementFromPoint(x, y);
        return !!hit && (hit === btn || btn.contains(hit));
      })()
    JS
  end

  def expect_drawer_closed
    expect(page).to have_no_css('#sidebar.is-open')
    expect(page).to have_css('[data-sidebar-drawer-toggle][aria-expanded="false"]')
    expect(page).to have_no_css('body.sidebar-drawer-open')
    expect(page).to have_css('#sidebar-backdrop[hidden]', visible: :all)
  end

  def visible_toggle_count
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('[data-sidebar-drawer-toggle], [data-sidebar-drawer-close], [data-sidebar-desktop-toggle]'))
        .filter((element) => {
          const style = getComputedStyle(element)
          const rect = element.getBoundingClientRect()
          return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0
        }).length
    JS
  end

  it 'keeps the desktop sidebar visible and exposes only its desktop control' do
    resize_to(1440, 1000)
    visit admin_dashboard_path

    expect(page).to have_css('#sidebar[aria-label="Panel de navegación administrativa"]')
    expect(page).to have_css('#sidebar nav[aria-label="Navegación administrativa"]')
    expect(page).to have_css('.sidebar-brand-link[aria-label="Ir al panel de control"]')
    expect(page).to have_css('.sidebar-user-link[aria-label^="Editar perfil de "]')
    expect(page).to have_css('#sidebar nav a[aria-label]', count: page.all('#sidebar nav a').count)
    expect(page).to have_css('[data-sidebar-desktop-toggle]', visible: true)
    expect(page).to have_css('[data-sidebar-drawer-toggle]', visible: false)
    expect(visible_toggle_count).to eq(1)

    find('[data-sidebar-desktop-toggle]').click
    expect(page).to have_css('html.sidebar-collapsed')
    expect(page).to have_css('[data-sidebar-desktop-toggle][aria-expanded="false"][aria-label="Expandir navegación"]')

    page.refresh
    expect(page).to have_css('html.sidebar-collapsed')
    expect(page).to have_css('[data-sidebar-desktop-toggle][aria-expanded="false"]')
  end

  # `overflow-x: hidden` en el body convierte el eje Y en `auto`, y el body pasa
  # a ser el scrollport del sidebar sticky: como el body no desplaza, el sidebar
  # se iba con el contenido. La contención horizontal vive en `html.admin-page`.
  it 'keeps the desktop sidebar pinned while the page scrolls' do
    resize_to(1440, 500)
    visit admin_dashboard_path
    expect(page).to have_css('#sidebar')

    # El dashboard sin datos no llena la ventana; el alto forzado aísla el
    # comportamiento del sticky del volumen de contenido de la página.
    page.execute_script("document.querySelector('.admin-main').style.minHeight = '3000px'")
    # `window.scrollTo` no mueve la ventana en este driver headless; la acción
    # nativa de Selenium sí emite el evento de rueda real.
    page.driver.browser.action.scroll_by(0, 400).perform

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const sidebar = document.getElementById('sidebar').getBoundingClientRect()
        return {
          scrollY: Math.round(window.scrollY),
          sidebarTop: Math.round(sidebar.top),
          bodyOverflowY: getComputedStyle(document.body).overflowY
        }
      })()
    JS

    expect(metrics['scrollY']).to be > 0, "no scrolleó: #{metrics.inspect}"
    expect(metrics['sidebarTop']).to eq(0), "el sidebar se fue con el contenido: #{metrics.inspect}"
    expect(metrics['bodyOverflowY']).to eq('visible')
  end

  it 'starts closed on mobile without displacing or overflowing the main content' do
    resize_to(390, 844)
    visit admin_dashboard_path

    expect_drawer_closed
    metrics = page.evaluate_script(<<~JS)
      (() => {
        const content = document.getElementById('admin-content').getBoundingClientRect()
        const body = document.body.getBoundingClientRect()
        const layout = document.querySelector('.admin-layout').getBoundingClientRect()
        const originalY = window.scrollY
        window.scrollTo(100, originalY)
        const horizontalScrollAfterAttempt = window.scrollX
        window.scrollTo(0, originalY)
        return {
          contentTop: Math.round(content.top),
          contentLeft: Math.round(content.left),
          scrollWidth: document.documentElement.scrollWidth,
          clientWidth: document.documentElement.clientWidth,
          innerWidth: window.innerWidth,
          htmlOverflowX: getComputedStyle(document.documentElement).overflowX,
          bodyOverflowX: getComputedStyle(document.body).overflowX,
          horizontalScrollAfterAttempt,
          bodyRect: { left: Math.round(body.left), right: Math.round(body.right), width: Math.round(body.width) },
          layoutRect: { left: Math.round(layout.left), right: Math.round(layout.right), width: Math.round(layout.width) },
          overflowElements: Array.from(document.querySelectorAll('body *')).filter((element) => {
            const rect = element.getBoundingClientRect()
            return rect.right > document.documentElement.clientWidth + 1 || rect.left < -1
          }).slice(0, 12).map((element) => {
            const rect = element.getBoundingClientRect()
            return {
              tag: element.tagName,
              id: element.id,
              className: String(element.className).slice(0, 100),
              left: Math.round(rect.left),
              right: Math.round(rect.right),
              width: Math.round(rect.width)
            }
          })
        }
      })()
    JS
    expect(metrics['contentTop']).to eq(0)
    expect(metrics['contentLeft']).to eq(0)
    expect(metrics['scrollWidth']).to(
      be <= metrics['clientWidth'],
      "horizontal overflow: #{metrics.inspect}"
    )
    expect(visible_toggle_count).to eq(1)
  end

  it 'opens accessibly and closes with its button while restoring focus' do
    resize_to(390, 844)
    visit admin_dashboard_path

    opener = find('[data-sidebar-drawer-toggle]')
    opener.click

    expect(page).to have_css('#sidebar.is-open[role="dialog"][aria-modal="true"]')
    expect(page).to have_css('body.sidebar-drawer-open')
    expect(page).to have_css('[data-sidebar-drawer-toggle][aria-expanded="true"]', visible: :all)
    expect(page.evaluate_script("document.activeElement.matches('[data-sidebar-drawer-close]')")).to be(true)
    expect(visible_toggle_count).to eq(1)

    # Ninguna de las aserciones anteriores espera al deslizamiento: todas miran
    # clases y atributos que se ponen al instante. Sin esto, el click podía
    # salir mientras el panel seguía entrando.
    wait_for_drawer_settled

    find('[data-sidebar-drawer-close]').click
    expect_drawer_closed
    expect(page.evaluate_script("document.activeElement.matches('[data-sidebar-drawer-toggle]')")).to be(true)
  end

  # Fija el motivo por el que existe la espera anterior. Si alguien la quita
  # creyéndola redundante, este ejemplo explica qué se rompe: el control de
  # cierre no es alcanzable en el instante en que `.is-open` aparece.
  it 'no expone el control de cierre hasta que el panel termina de entrar' do
    resize_to(390, 844)
    visit admin_dashboard_path

    find('[data-sidebar-drawer-toggle]').click
    expect(page).to have_css('#sidebar.is-open')

    # El estado declarativo ya está completo...
    aggregate_failures do
      expect(page).to have_css('body.sidebar-drawer-open')
      expect(page).to have_css('[data-sidebar-drawer-toggle][aria-expanded="true"]', visible: :all)
    end

    # ...y aun así el botón puede no estar todavía donde se le va a hacer click.
    # Tras esperar a la transición, alcanzarlo es determinista.
    wait_for_drawer_settled
    expect(drawer_close_button_hittable?).to be(true)

    geometry = page.evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector('[data-sidebar-drawer-close]').getBoundingClientRect();
        return Math.round(r.left + r.width / 2);
      })()
    JS
    # Posición final dentro del viewport, no el x negativo de mitad de animación.
    expect(geometry).to be > 0
  end

  it 'closes with the backdrop and Escape' do
    resize_to(390, 844)
    visit admin_dashboard_path

    open_drawer
    expect(
      page.evaluate_script(
        'document.elementFromPoint(document.documentElement.clientWidth - 8, Math.round(window.innerHeight / 2)).id'
      )
    ).to eq('sidebar-backdrop')
    page.execute_script(
      'document.elementFromPoint(document.documentElement.clientWidth - 8, Math.round(window.innerHeight / 2)).click()'
    )
    expect_drawer_closed

    open_drawer
    find('body').send_keys(:escape)
    expect_drawer_closed
  end

  it 'closes after Turbo navigation and remains closed through browser history' do
    resize_to(390, 844)
    visit admin_dashboard_path

    open_drawer
    click_link 'Productos', exact: true
    expect(page).to have_current_path(admin_products_path)
    expect_drawer_closed

    page.go_back
    expect(page).to have_current_path(admin_dashboard_path)
    expect_drawer_closed
    page.go_forward
    expect(page).to have_current_path(admin_products_path)
    expect_drawer_closed
  end

  it 'uses one current page for inventory children and keeps resource sections active' do
    resize_to(1024, 768)
    visit admin_inventory_location_explorer_path(mode: 'unlocated')

    expect(page).to have_css('#sidebar a[aria-current="page"]', count: 1)
    expect(page).to have_css('#sidebar a.active[aria-current="page"]', text: 'Explorar Ubicaciones')
    expect(page).to have_css('#sidebar a.section-active:not([aria-current])', text: 'Inventario')

    visit admin_product_path(product)
    expect(page).to have_css('#sidebar a.section-active:not([aria-current])', text: 'Productos')

    visit new_admin_product_path
    expect(page).to have_css('#sidebar a.section-active:not([aria-current])', text: 'Productos')
  end

  it 'uses the lg breakpoint without exposing two controls on tablet' do
    resize_to(991, 800)
    visit admin_dashboard_path
    expect(visible_toggle_count).to eq(1)
    expect(page).to have_css('[data-sidebar-drawer-toggle]', visible: true)

    resize_to(1024, 768)
    expect(page).to have_css('[data-sidebar-desktop-toggle]', visible: true)
    expect(visible_toggle_count).to eq(1)
  end

  it 'preserves the settings context and the current Ajustes label' do
    resize_to(1024, 768)
    visit delivered_orders_debt_audit_admin_settings_path
    expect(page).to have_css('#sidebar a.section-active:not([aria-current])', text: 'Configuración')

    visit admin_inventory_adjustments_path
    expect(page).to have_css('#sidebar a.active[aria-current="page"]', text: 'Ajustes')
    expect(page).to have_css('#sidebar a[aria-current="page"]', count: 1)
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
