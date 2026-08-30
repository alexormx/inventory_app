require 'rails_helper'
# spec/system/user_login_spec.rb
Selenium::WebDriver.logger.level = :warn

RSpec.describe "User login/logout", type: :system do
  let!(:user) { create(:user, email: "user@example.com", password: "password123") }

  after(:each, :js) do
    page.driver.browser.execute_cdp("Emulation.setCPUThrottlingRate", rate: 1)
  end

  # ✅ Successful login and logout
  #
  it "successful login and logout", js: true do
    visit new_user_session_path
    accept_cookies_if_present
    page.driver.browser.execute_cdp("Emulation.setCPUThrottlingRate", rate: 6)
    # Simulate a delayed Stimulus connection across the Turbo login render.
    # The account dropdown has a synchronous, idempotent turbo:render owner, so
    # its first click must still work instead of being lost in the connect gap.
    page.execute_script("window.Stimulus.stop()")
    fill_in "user[email]", with: "user@example.com"
    fill_in "user[password]", with: "password123"
    click_button "Iniciar sesión"

    expect(page).to have_content("Sesión iniciada.")

    if page.has_selector?("#hamburger", wait: 3)
      find("#hamburger").click
    end

    # Wait for the real lifecycle readiness marker, not mere DOM visibility.
    expect(page).to have_selector("#account[data-dropdown-enhanced='1']", visible: true)
    # DIAGNÓSTICO TEMPORAL (rama desechable): mismo click de Capybara, pero con
    # telemetría alrededor. Si entrega eventos, el test sigue igual; si vuelve
    # sin generar ninguno, se ejecuta UNA acción W3C en el mismo estado y el
    # ejemplo falla a propósito con la clasificación.
    diag_env!
    diag_click_account!

    expect(page).to have_selector("#account[aria-expanded='true']", visible: true)
    expect(page).to have_selector("#account-menu.show #logout-button", visible: true)

    # One click must cause exactly one transition, including after another
    # Turbo visit where the replacement navbar is enhanced again.
    find("#account").click
    expect(page).to have_selector("#account[aria-expanded='false']", visible: true)
    expect(page).to have_no_selector("#account-menu.show")

    find("#account").click
    click_link "Mi Perfil"
    expect(page).to have_current_path(profile_path)
    expect(page).to have_selector("#account[data-dropdown-enhanced='1']", visible: true)
    find("#account").click
    expect(page).to have_selector("#account[aria-expanded='true']", visible: true)
    expect(page).to have_selector("#account-menu.show #logout-button", visible: true)

    find("#logout-button").click

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
