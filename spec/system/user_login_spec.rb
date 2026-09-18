require 'rails_helper'
# spec/system/user_login_spec.rb
Selenium::WebDriver.logger.level = :warn

RSpec.describe "User login/logout", type: :system do
  let!(:user) { create(:user, email: "user@example.com", password: "password123") }

  # ✅ Successful login
  #
  # Bloqueante. Prueba el inicio de sesión por UI real y que la sesión
  # resultante da acceso a una ruta autenticada. No cierra sesión: el cierre
  # por navegador vive en el ejemplo en cuarentena de abajo, y su semántica de
  # backend está cubierta de forma determinista en
  # spec/requests/user_session_lifecycle_spec.rb.
  #
  # El desplegable de cuenta tiene su propia cobertura determinista en
  # spec/system/dropdown_enhancement_spec.rb, así que aquí no se repite.
  it "successful login", js: true do
    visit new_user_session_path
    accept_cookies_if_present

    fill_in "user[email]", with: "user@example.com"
    fill_in "user[password]", with: "password123"
    click_button "Iniciar sesión"

    expect(page).to have_content("Sesión iniciada.")

    visit profile_path
    expect(page).to have_current_path(profile_path)
    expect(page).to have_content("Configuración de Cuenta")
  end

  # ⚠️ EN CUARENTENA — no bloquea el merge. Ver
  # .github/workflows/browser-input-diagnostic.yml para el porqué, el alcance
  # y la condición de salida.
  #
  # No está en cuarentena porque el comportamiento de la aplicación esté sin
  # probar. El cierre de sesión está cubierto de forma bloqueante y
  # determinista en spec/requests/user_session_lifecycle_spec.rb (semántica de
  # la sesión y los dos controles reales de logout) y el ciclo de vida del
  # desplegable en spec/system/dropdown_enhancement_spec.rb.
  #
  # Lo que no se puede usar como puerta de merge es este click concreto: hay
  # evidencia repetida en CI de que Chrome acepta los comandos de entrada CDP
  # (mouseMoved/mousePressed/mouseReleased, misma sesión, mismo target, mismo
  # frame, mismo renderer, coordenadas correctas) sin que se materialice
  # ningún evento en el DOM ni salga petición alguna al servidor. Se reprodujo
  # con el par desalineado del runner y con pares exactos de Chrome 151 y 152.
  # La evidencia completa queda en el historial de PRs de diagnóstico.
  it "successful logout through the real browser", :browser_input_quarantine, js: true do
    visit new_user_session_path
    accept_cookies_if_present

    fill_in "user[email]", with: "user@example.com"
    fill_in "user[password]", with: "password123"
    click_button "Iniciar sesión"

    expect(page).to have_content("Sesión iniciada.")

    visit profile_path
    expect(page).to have_current_path(profile_path)
    expect(page).to have_content("Configuración de Cuenta")

    # DIAGNOSTICO TEMPORAL — rama desechable, no mergear. No es una correccion.
    #
    # Ultimo brazo del A/B. Con el snapshot completo de estado la entrega nula
    # no se reprodujo en 8 ejecuciones; conservando SOLO el viaje de ida y
    # vuelta de WebDriver (`evaluate_script('1')`) volvio a la primera. Asi que
    # lo que enmascaraba el fallo no era el tiempo transcurrido, sino algo del
    # trabajo que el snapshot hacia en el renderer.
    #
    # Aqui queda una unica operacion de DOM: la consulta de hit-test. No se
    # miden geometrias ni estilos, que es justo lo que se quiere separar.
    #
    # La coordenada va fija a proposito: derivarla con getBoundingClientRect
    # reintroduciria la medicion de layout que este brazo intenta aislar. Es
    # estable y esta comprobada: en C2, C3, C4 y C8 el boton ocupa exactamente
    # 525.5,749.73 806x43.59 en un viewport de 1440x857, su centro cae en
    # (928, 771), y elementFromPoint devuelve ahi el propio BUTTON. Es tambien
    # la coordenada exacta que ChromeDriver despacho en la reproduccion
    # instrumentada.
    #
    # No se inspecciona el nodo devuelto: interesa forzar el hit-test, no
    # afirmar su resultado.
    page.evaluate_script('(function () { document.elementFromPoint(928, 771); return 1; })()')

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
