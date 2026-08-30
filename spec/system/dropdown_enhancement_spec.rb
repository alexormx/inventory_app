# frozen_string_literal: true

require 'rails_helper'

# Turbo snapshots clone DOM attributes but not listeners attached to individual
# nodes. A serialized `data-dropdown-enhanced="1"` therefore used to make the
# restored node look ready while the direct click listener was gone. The
# polyfill now owns Bootstrap-style dropdowns through one document listener,
# whose lifetime is independent of the restored toggle node.
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

  def build_dual_owned_dropdown!
    page.execute_script(<<~JS)
      (() => {
        document.getElementById('dual-owner-host')?.remove();
        const host = document.createElement('div');
        host.id = 'dual-owner-host';
        host.className = 'dropdown';
        host.dataset.controller = 'dropdown';
        host.innerHTML = `
          <button type="button" id="dual-owner-toggle"
                  data-bs-toggle="dropdown"
                  data-dropdown-target="button"
                  data-action="click->dropdown#toggle"
                  aria-expanded="false">Dual owner</button>
          <ul class="dropdown-menu" id="dual-owner-menu" data-dropdown-target="menu">
            <li><a class="dropdown-item" href="#x">Item</a></li>
          </ul>`;
        document.body.appendChild(host);
      })()
    JS
  end

  def build_stimulus_owned_dropdown!
    page.execute_script(<<~JS)
      (() => {
        document.getElementById('stimulus-owner-host')?.remove();
        const host = document.createElement('div');
        host.id = 'stimulus-owner-host';
        host.className = 'dropdown';
        host.dataset.controller = 'dropdown';
        host.innerHTML = `
          <button type="button" id="stimulus-owner-toggle"
                  data-dropdown-target="button"
                  data-action="click->dropdown#toggle"
                  aria-expanded="false">Stimulus owner</button>
          <ul class="dropdown-menu" id="stimulus-owner-menu" data-dropdown-target="menu">
            <li><a class="dropdown-item" href="#x">Item</a></li>
          </ul>`;
        document.body.appendChild(host);
      })()
    JS
  end

  def start_stimulus_and_wait_for!(element_id)
    page.evaluate_async_script(<<~JS, element_id)
      const elementId = arguments[0];
      const done = arguments[arguments.length - 1];

      Promise.resolve(window.Stimulus.start()).then(() => {
        const waitForController = () => {
          const element = document.getElementById(elementId);
          const controller = element &&
            window.Stimulus.getControllerForElementAndIdentifier(element, 'dropdown');

          if (controller) done(true);
          else requestAnimationFrame(waitForController);
        };

        waitForController();
      });
    JS
  end

  def observe_aria_transitions!(toggle_id)
    page.execute_script(<<~JS, toggle_id)
      (() => {
        const toggle = document.getElementById(arguments[0]);
        window.__dropdownAriaTransitions = 0;
        window.__dropdownAriaObserver?.disconnect();
        window.__dropdownAriaObserver = new MutationObserver((records) => {
          window.__dropdownAriaTransitions += records.filter(
            (record) => record.attributeName === 'aria-expanded'
          ).length;
        });
        window.__dropdownAriaObserver.observe(toggle, {
          attributes: true,
          attributeFilter: ['aria-expanded']
        });
      })()
    JS
  end

  def aria_transition_count
    page.evaluate_script('window.__dropdownAriaTransitions')
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

  it 'produces one transition when the initializer runs again' do
    build_dropdown!(with_menu: true)
    run_initializer!
    expect(enhanced?).to be(true)

    run_initializer!
    run_initializer!

    find('#probe-toggle').click

    aggregate_failures do
      expect(page).to have_css('#probe-menu.show')
      expect(menu_open?).to be(true)
    end
  end

  it 'keeps a marked dropdown operable after serialized DOM restoration' do
    build_dropdown!(with_menu: true)
    run_initializer!
    expect(enhanced?).to be(true)

    # Turbo snapshots clone the DOM. Attributes survive; node-bound listeners do not.
    page.execute_script(<<~JS)
      (() => {
        const current = document.getElementById('probe-host');
        current.replaceWith(current.cloneNode(true));
        document.dispatchEvent(new Event('turbo:render'));
      })()
    JS

    find('#probe-toggle').click

    aggregate_failures do
      expect(page).to have_css('#probe-menu.show')
      expect(page).to have_css("#probe-toggle[aria-expanded='true']")
    end
  end

  it 'opens on the first click after a real Turbo history restoration' do
    user = create(:user, email: 'restored-dropdown@example.com', password: 'password123')
    sign_in user
    visit root_path
    accept_cookies_if_present

    expect(page).to have_css("#account[data-dropdown-enhanced='1']", visible: true)
    find('#account').click
    click_link 'Mi Perfil'
    expect(page).to have_current_path(profile_path)

    page.go_back
    expect(page).to have_current_path(root_path)
    expect(page).to have_css("#account[data-dropdown-enhanced='1']", visible: true)
    find('#account').click

    aggregate_failures do
      expect(page).to have_css("#account[aria-expanded='true']")
      expect(page).to have_css('#account-menu.show')
    end
  end

  it 'hands fallback ownership to Stimulus without double toggling' do
    page.execute_script('window.Stimulus.stop()')
    build_dual_owned_dropdown!
    run_initializer!

    expect(page).to have_css("#dual-owner-toggle[data-dropdown-enhanced='1']")

    # The fallback owns the control while Stimulus is unavailable.
    find('#dual-owner-toggle').click
    expect(page).to have_css("#dual-owner-toggle[aria-expanded='true']")
    find('#dual-owner-toggle').click
    expect(page).to have_css("#dual-owner-toggle[aria-expanded='false']")

    start_stimulus_and_wait_for!('dual-owner-host')
    observe_aria_transitions!('dual-owner-toggle')
    find('#dual-owner-toggle').click

    aggregate_failures do
      expect(page).to have_css("#dual-owner-toggle[aria-expanded='true']")
      expect(page).to have_css('#dual-owner-menu.show')
      expect(aria_transition_count).to eq(1)
    end
  end

  it 'lets connected Stimulus own exactly one transition' do
    build_stimulus_owned_dropdown!
    start_stimulus_and_wait_for!('stimulus-owner-host')
    observe_aria_transitions!('stimulus-owner-toggle')

    find('#stimulus-owner-toggle').click

    aggregate_failures do
      expect(page).to have_css("#stimulus-owner-toggle[aria-expanded='true']")
      expect(page).to have_css('#stimulus-owner-menu.show')
      expect(aria_transition_count).to eq(1)
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
