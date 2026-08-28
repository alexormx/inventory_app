# frozen_string_literal: true

require 'rails_helper'

# `data-dropdown-enhanced` cumple dos papeles a la vez: es la guarda de
# idempotencia que impide enlazar el listener dos veces, y es la señal de que el
# control ya responde a un click.
#
# Por eso el orden importa. Si se escribe antes de validar el menú y antes de
# `addEventListener`, un botón que llega al DOM sin su menú queda marcado como
# mejorado para siempre y sin listener: todo pase posterior del ciclo de Turbo
# lo salta por la guarda, y el usuario hace click y no pasa nada.
#
# Un artifact de CI (run 33140802080) capturó exactamente ese estado en
# producción de pruebas: `#account` con data-dropdown-enhanced="1" y
# aria-expanded="false", con `#account-menu` presente pero sin `show`.
RSpec.describe 'Dropdown enhancement lifecycle', :js, type: :system do
  before { driven_by :selenium_chrome_headless }

  # Los polyfills escuchan turbo:render, que es la ruta real por la que se
  # re-inicializan los controles tras una navegación de Turbo.
  def run_initializer!
    page.execute_script("document.dispatchEvent(new Event('turbo:render'))")
  end

  def build_dropdown!(with_menu:)
    page.execute_script(<<~JS)
      (() => {
        document.getElementById('probe-host')?.remove();
        const host = document.createElement('div');
        host.id = 'probe-host';
        host.innerHTML = `
          <div class="dropdown">
            <button type="button" id="probe-toggle" data-bs-toggle="dropdown" aria-expanded="false">Probe</button>
            #{with_menu ? '<ul class="dropdown-menu" id="probe-menu"><li><a class="dropdown-item" href="#x">Item</a></li></ul>' : ''}
          </div>`;
        document.body.appendChild(host);
      })()
    JS
  end

  def add_menu_later!
    page.execute_script(<<~JS)
      (() => {
        const parent = document.getElementById('probe-toggle').closest('.dropdown');
        const ul = document.createElement('ul');
        ul.className = 'dropdown-menu';
        ul.id = 'probe-menu';
        ul.innerHTML = '<li><a class="dropdown-item" href="#x">Item</a></li>';
        parent.appendChild(ul);
      })()
    JS
  end

  def enhanced?
    page.evaluate_script("document.getElementById('probe-toggle').dataset.dropdownEnhanced === '1'")
  end

  def menu_open?
    page.evaluate_script("document.getElementById('probe-menu')?.classList.contains('show') === true")
  end

  before do
    visit root_path
    accept_cookies_if_present
  end

  it 'does not mark a button as enhanced while its menu is missing' do
    build_dropdown!(with_menu: false)
    run_initializer!

    expect(enhanced?).to be(false)
  end

  it 'enhances the button once the menu appears on a later initializer pass' do
    build_dropdown!(with_menu: false)
    run_initializer!
    expect(enhanced?).to be(false)

    add_menu_later!
    run_initializer!

    aggregate_failures do
      expect(enhanced?).to be(true)
      find('#probe-toggle').click
      expect(page).to have_css('#probe-menu.show')
      expect(page).to have_css("#probe-toggle[aria-expanded='true']")
    end
  end

  it 'does not attach a duplicate listener when the initializer runs again' do
    build_dropdown!(with_menu: true)
    run_initializer!
    expect(enhanced?).to be(true)

    # Un segundo listener haría que un solo click ejecutase toggle() dos veces,
    # abriendo y cerrando: el menú quedaría cerrado en vez de abierto.
    run_initializer!
    run_initializer!

    find('#probe-toggle').click

    aggregate_failures do
      expect(page).to have_css('#probe-menu.show')
      expect(menu_open?).to be(true)
    end
  end

  it 'opens and closes the real account dropdown for a signed-in user' do
    user = create(:user, email: 'dropdown@example.com', password: 'password123')
    sign_in user
    visit root_path
    accept_cookies_if_present

    find('#hamburger').click if page.has_selector?('#hamburger', wait: 2)

    expect(page).to have_css("#account[data-dropdown-enhanced='1']", visible: true)
    find('#account').click

    aggregate_failures do
      expect(page).to have_css("#account[aria-expanded='true']")
      expect(page).to have_css('#account-menu.show')
    end

    find('#account').click

    aggregate_failures do
      expect(page).to have_css("#account[aria-expanded='false']")
      expect(page).to have_no_css('#account-menu.show')
    end
  end
end
