require 'rails_helper'
# spec/system/user_login_spec.rb
RSpec.describe "User login/logout", type: :system do
  let!(:user) { create(:user, email: "user@example.com", password: "password123") }

  # ✅ Successful login and logout
  #
  it "successful login and logout", js: true do
    visit new_user_session_path
    fill_in "user[email]", with: "user@example.com"
    fill_in "user[password]", with: "password123"
    click_button "Iniciar sesión"

    expect(page).to have_content("Sesión iniciada.")

    if page.has_selector?("#hamburger", wait: 3)
      find("#hamburger").click
    end
    
    expect(page).to have_selector("#account", visible: :all)
    
    # Use Capybara click instead of JS where possible
    find("#account").click

    # Check if the logout button is visible
    # and click it
    expect(page).to have_selector("#logout-button", visible: true)
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
    click_button "Iniciar sesión"
  
    expect(page).to have_content("Correo electrónico o password inválido(s)")
  end

  # ✅ Redirect logged-in users away from login page
  it "redirects logged-in users away from login page", js: true do
    visit new_user_session_path
  
    fill_in "user[email]", with: "user@example.com"
    fill_in "user[password]", with: "password123"
    click_button "Iniciar sesión"

    expect(page).to have_content("Sesión iniciada.")
  
    # Try to visit login page again
    visit new_user_session_path
    expect(page).to have_current_path(root_path) # Redirected to homepage
  end
end