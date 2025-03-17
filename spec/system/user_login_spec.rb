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

    # ✅ Open the hamburger (responsive navbar) if required
    find("#hamburger").click


    # ✅ Use existing dropdown ID
    expect(page).to have_selector("#account", visible: :all)
    
    # Using execute_script due to Bootstrap dropdown interaction 
    # timing and visibility issues in Capybara tests.
    page.execute_script("document.querySelector('#account').click()")
    page.execute_script("document.querySelector('#logout-button').click()")

    expect(page).to have_content("Signed out successfully.", wait: 5)
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