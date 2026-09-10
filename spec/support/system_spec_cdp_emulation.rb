# frozen_string_literal: true

# La emulación CDP (throttling de CPU, entre otras) se aplica al NAVEGADOR, no a
# la sesión: ni `Capybara.reset_sessions!` ni `driven_by` la revierten, y
# Selenium reutiliza el mismo objeto de navegador entre ejemplos (verificado:
# mismo object_id en ejemplos consecutivos). Un spec que estrangula la CPU para
# simular lentitud podía así dejar toda la suite estrangulada.
#
# Vive aquí, y no en línea dentro del hook, para que la garantía sea verificable
# sin medir tiempos de ejecución: se puede comprobar el comando exacto y la tasa
# solicitada, y se puede comprobar entre ejemplos que el hook la restableció.
module SystemSpecCdpEmulation
  COMMAND = 'Emulation.setCPUThrottlingRate'
  RESET_RATE = 1

  class << self
    # Última tasa solicitada. Los specs de aislamiento la usan para comprobar,
    # sin cronómetros, que el hook global corrió antes del cuerpo del ejemplo.
    attr_accessor :last_requested_rate

    def reset!(browser)
      request(browser, RESET_RATE)
    end

    # Devuelve true si el comando salió, false si el navegador no pudo
    # atenderlo. Se rescata StandardError a propósito: el hook corre antes de
    # CADA ejemplo js y no debe tumbar la suite si el driver no soporta CDP o la
    # sesión ya murió. Devolver un booleano en vez de nil deja esa decisión
    # observable desde los tests en lugar de silenciosa.
    def request(browser, rate)
      browser.execute_cdp(COMMAND, rate: rate)
      self.last_requested_rate = rate
      true
    rescue StandardError
      false
    end
  end
end
