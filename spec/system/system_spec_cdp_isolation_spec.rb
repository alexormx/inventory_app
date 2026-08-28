# frozen_string_literal: true

require 'rails_helper'

# Fija el aislamiento de la emulación CDP, igual que
# [[system_spec_window_isolation_spec]] hace con el viewport.
#
# El throttling de CPU se aplica al navegador, no a la sesión: ni
# `Capybara.reset_sessions!` ni `driven_by` lo revierten. Medido antes de
# centralizar el reset: 17 ms de referencia, 65 ms con throttle 6x, y 63 ms en
# el ejemplo siguiente que nunca lo pidió. Un spec que simula lentitud podía
# así dejar toda la suite estrangulada y tumbar un ejemplo interactivo
# cualquiera, distinto en cada corrida.
#
# Si alguien quita el reset del hook global, esto se pone rojo aquí y no tres
# semanas después en un spec que no tiene nada que ver.
RSpec.describe 'System spec CDP emulation isolation', :js, type: :system do
  # Bucle puramente aritmético: su duración depende del throttling de CPU y no
  # de la red ni del renderizado.
  def busy_ms
    page.evaluate_script(<<~JS)
      (() => {
        const started = performance.now();
        let sink = 0;
        for (let i = 0; i < 3000000; i++) { sink += i % 7; }
        return Math.round(performance.now() - started);
      })()
    JS
  end

  it 'mide una referencia sin estrangular y deja el throttle puesto' do
    visit root_path
    baseline = busy_ms
    page.driver.browser.execute_cdp('Emulation.setCPUThrottlingRate', rate: 6)

    # A propósito NO se restablece: el ejemplo siguiente debe encontrarlo limpio
    # por el hook global, no por cortesía de éste.
    expect(busy_ms).to be > baseline
  end

  it 'arranca el ejemplo siguiente sin throttling heredado' do
    visit root_path

    # Con la fuga presente esto rondaba los 60 ms; sin ella baja a la decena.
    expect(busy_ms).to be < 40
  end
end
