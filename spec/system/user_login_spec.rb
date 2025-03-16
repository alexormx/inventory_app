require 'rails_helper'
# spec/system/user_login_spec.rb
RSpec.describe "User login/logout", type: :system do
  let!(:user) { create(:user, email: "user@example.com", password: "password123") }

  # ✅ Successful login and logout
  #
  it "successful login and logout", js: true do
    visit new_user_session_path
    fill_in "Email", with: "user@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"

    expect(page).to have_content("Signed in successfully.")

    find(".navbar-toggler").click # Open the mobile menu
    find("#userDropdown").click # Open the dropdown
    click_link "Cerrar sesión" # Click the sign-out link
    expect(page).to have_content("Signed out successfully.")
  end

  # ✅ Login fails with invalid credentials
  it "login fails with invalid credentials" do
    visit new_user_session_path

    fill_in "Email", with: "wrong@example.com"
    fill_in "Password", with: "wrongpassword"
    click_button "Log in"

    expect(page).to have_content("Invalid Email or password.")
  end
end