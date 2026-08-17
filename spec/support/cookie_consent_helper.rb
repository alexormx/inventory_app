# frozen_string_literal: true

# El banner de cookies tapa la página con #cookie-overlay hasta que se acepta, y
# Chrome rechaza cualquier clic que caiga debajo (ElementClickInterceptedError).
# Aceptarlo es justo lo que hace una persona real, así que los specs pasan por el
# mismo botón en lugar de esconder el overlay por JS: si el banner se rompe, los
# specs se enteran.
#
# Espera a que el overlay desaparezca, de modo que el clic siguiente no compita
# con la animación de salida.
module CookieConsentHelper
  def accept_cookies_if_present
    return unless page.has_button?('Aceptar', wait: 2)

    click_button 'Aceptar'
    expect(page).to have_no_css('#cookie-overlay', visible: true)
  end
end

RSpec.configure do |config|
  config.include CookieConsentHelper, type: :system
end
