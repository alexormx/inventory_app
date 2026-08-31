require 'rails_helper'
# spec/system/user_login_spec.rb
Selenium::WebDriver.logger.level = :warn

RSpec.describe "User login/logout", type: :system do
  let!(:user) { create(:user, email: "user@example.com", password: "password123") }

  # ✅ Successful login and logout
  #
  # Este ejemplo prueba AUTENTICACIÓN y nada más. Antes también ejercitaba el
  # ciclo de vida del desplegable de cuenta bajo condiciones adversarias que él
  # mismo creaba (throttle de CPU 6 y Stimulus detenido), con cuatro clicks
  # sobre #account. Eso mezclaba dos responsabilidades y ataba el login a una
  # falla de entrada de eventos del navegador ya diagnosticada: en el estado
  # capturado, tanto WebElement.click como una acción de puntero W3C entregaron
  # CERO eventos sobre el mismo nodo conectado y sin mover.
  #
  # El desplegable tiene su propia cobertura determinista en
  # spec/system/dropdown_enhancement_spec.rb: guarda de mejora, mejora tardía,
  # una sola transición por click, apertura/cierre real, reinicio del
  # inicializador, restauración serializada del DOM, primer click tras una
  # restauración real de historial de Turbo, y el relevo entre el fallback y
  # Stimulus. Aquí ya no se repite nada de eso.
  #
  # La sesión se cierra desde el control de la página de perfil, que es UI de
  # producto normal y no depende del menú desplegable.
  it "successful login and logout", js: true do
    visit new_user_session_path
    accept_cookies_if_present

    fill_in "user[email]", with: "user@example.com"
    fill_in "user[password]", with: "password123"
    click_button "Iniciar sesión"

    expect(page).to have_content("Sesión iniciada.")

    visit profile_path
    expect(page).to have_current_path(profile_path)
    expect(page).to have_content("Configuración de Cuenta")

    # DIAGNOSTICO TEMPORAL — rama desechable, no mergear.
    #
    # Brazo A/B. El snapshot de estado del experimento anterior hacia dos cosas
    # a la vez justo antes de este click: un viaje de ida y vuelta de WebDriver,
    # y trabajo real del renderer (elementFromPoint fuerza hit-test,
    # getBoundingClientRect y getComputedStyle fuerzan estilo y layout). Con el
    # snapshot completo la entrega nula no se reprodujo en 8 ejecuciones, pero
    # no se puede saber cual de las dos cosas la enmascaraba.
    #
    # Este brazo conserva SOLO el viaje de ida y vuelta y elimina todo el
    # trabajo del renderer: evalua una expresion literal, sin consultar el DOM.
    # No es una correccion ni pretende serlo.
    page.evaluate_script('1')

    click_button "Cerrar sesión"

    expect(page).to have_content("Sesión finalizada.")
  end

  # ✅ Login fails with invalid credentials
  it "login fails with invalid credentials" do
    visit new_user_session_path

    fill_in "user[email]", with: "wrong@example.com"
    fill_in "user[password]", with: "wrongpassword"
    click_button "Iniciar sesión"

    expect(page).to have_content("Correo electrónico o password inválido(s)")
  end

  # ✅ Login fails with empty fields
  it "fails to login with empty fields", js: true do
    visit new_user_session_path
    accept_cookies_if_present
    click_button "Iniciar sesión"
  
    expect(page).to have_content("Correo electrónico o password inválido(s)")
  end

  # ✅ Redirect logged-in users away from login page
  it "redirects logged-in users away from login page", js: true do
    visit new_user_session_path
    accept_cookies_if_present

    fill_in "user[email]", with: "user@example.com"
    fill_in "user[password]", with: "password123"
    click_button "Iniciar sesión"

    expect(page).to have_content("Sesión iniciada.")
  
    # Try to visit login page again
    visit new_user_session_path
    expect(page).to have_current_path(root_path) # Redirected to homepage
  end
end
