# frozen_string_literal: true

# El banner de cookies va fijo abajo y tapa lo que quede debajo de él; Chrome
# rechaza cualquier clic que caiga ahí (ElementClickInterceptedError).
# Aceptarlo es justo lo que hace una persona real, así que los specs pasan por el
# mismo botón en lugar de esconder el overlay por JS: si el banner se rompe, los
# specs se enteran.
#
# Espera a que el banner desaparezca, de modo que el clic siguiente no compita
# con él.
module CookieConsentHelper
  def accept_cookies_if_present
    return unless page.has_button?('Aceptar', wait: 2)

    click_button 'Aceptar'
    expect(page).to have_no_css('#cookie-banner', visible: :all)
  end
end

RSpec.configure do |config|
  config.include CookieConsentHelper, type: :system
end
