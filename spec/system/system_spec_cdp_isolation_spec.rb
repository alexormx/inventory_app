# frozen_string_literal: true

require 'rails_helper'

# Fija el aislamiento de la emulación CDP, igual que
# [[system_spec_window_isolation_spec]] hace con el viewport.
#
# El throttling de CPU se aplica al navegador, no a la sesión: ni
# `Capybara.reset_sessions!` ni `driven_by` lo revierten, y Selenium reutiliza el
# mismo objeto de navegador entre ejemplos. Sin restablecerlo al entrar a cada
# ejemplo, un spec que simula lentitud dejaba estrangulada al resto de la suite
# y tumbaba un ejemplo interactivo cualquiera, distinto en cada corrida.
#
# La versión anterior de este spec deducía el estado del throttle CRONOMETRANDO
# un bucle de cómputo, y era inestable por construcción: la primera medición
# ocurre con el JIT frío, así que una referencia inflada podía superar a la
# medición ya estrangulada. Ocurrió de verdad en dos corridas de la suite
# completa: `expected: > 24, got: 12` y `expected: > 17, got: 13` — es decir, el
# valor CON throttle salió MENOR que la referencia, cosa imposible si el
# cronómetro fuese fiable. El reset funcionaba; la aserción no.
#
# Aquí se comprueba el comando y la tasa de forma directa, sin depender del
# rendimiento de la máquina.
RSpec.describe 'System spec CDP emulation isolation' do
  describe SystemSpecCdpEmulation do
    # Doble simple y no verificador a propósito: Selenium expone `execute_cdp`
    # por delegación, no como método de instancia declarado, así que
    # `instance_double` lo rechaza. Lo que se comprueba aquí es el contrato que
    # este helper emite hacia el navegador.
    it 'pide exactamente el comando y la tasa de reset' do
      browser = double('browser')
      expect(browser).to receive(:execute_cdp).with('Emulation.setCPUThrottlingRate', rate: 1)

      expect(described_class.reset!(browser)).to be(true)
    end

    it 'registra la tasa solicitada' do
      browser = double('browser')
      allow(browser).to receive(:execute_cdp)

      described_class.request(browser, 6)

      expect(described_class.last_requested_rate).to eq(6)
    end

    # El hook corre antes de CADA ejemplo js: si el driver no soporta CDP o la
    # sesión ya murió, no debe tumbar la suite entera. Se comprueba que la
    # decisión de tragarse el error es deliberada y observable.
    it 'informa del fallo en vez de propagarlo cuando el navegador no responde' do
      browser = double('browser')
      allow(browser).to receive(:execute_cdp).and_raise(
        Selenium::WebDriver::Error::WebDriverError.new('session deleted')
      )

      expect { described_class.reset!(browser) }.not_to raise_error
      expect(described_class.reset!(browser)).to be(false)
    end
  end

  # Los dos ejemplos siguientes van en pareja y en orden: el primero deja el
  # navegador estrangulado a propósito, y el segundo comprueba que el hook global
  # lo restableció ANTES de ejecutar su cuerpo. Es la garantía real que interesa,
  # no que exista un método.
  describe 'entre ejemplos', :js, type: :system do
    it 'deja el navegador estrangulado a propósito' do
      visit root_path

      SystemSpecCdpEmulation.request(page.driver.browser, 6)

      # A propósito NO se restablece aquí: el ejemplo siguiente debe encontrarlo
      # limpio por el hook global, no por cortesía de éste.
      expect(SystemSpecCdpEmulation.last_requested_rate).to eq(6)
    end

    it 'arranca el ejemplo siguiente con el throttle ya restablecido' do
      # Sin el reset en el hook global, esto seguiría valiendo 6 al llegar aquí.
      expect(SystemSpecCdpEmulation.last_requested_rate).to eq(SystemSpecCdpEmulation::RESET_RATE)
    end
  end
end
