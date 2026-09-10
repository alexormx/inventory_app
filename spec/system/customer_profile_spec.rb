# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Customer profile navigation', type: :system do
  it 'opens a profile with a saved address through the real account menu', js: true do
    customer = create(:user, name: 'Ana Cliente', notes: 'PRIVATE-ADMIN-NOTE')
    create(:shipping_address, user: customer, full_name: 'Ana Destinataria', line1: 'Calle Roble 123')

    visit new_user_session_path
    accept_cookies_if_present
    fill_in 'user[email]', with: customer.email
    fill_in 'user[password]', with: 'password123'
    click_button 'Iniciar sesión'
    expect(page).to have_content('Sesión iniciada.')

    expect(page).to have_css("#account[data-dropdown-enhanced='1']")
    find('#account').click
    click_link 'Mi Perfil'

    expect(page).to have_current_path(profile_path)
    expect(page).to have_content('Ana Cliente')
    expect(page).to have_content('Ana Destinataria')
    expect(page).to have_content('Calle Roble 123')
    expect(page).to have_content('Configuración de Cuenta')
    expect(page).to have_no_content('PRIVATE-ADMIN-NOTE')
    expect(page).to have_no_link('Admin')

    # Exercise the real DELETE form without the quarantined Chrome logout click.
    page.execute_script("document.querySelector('main form[action=\"/users/sign_out\"]').requestSubmit()")
    expect(page).to have_content('Sesión finalizada.')
    visit profile_path
    expect(page).to have_current_path(new_user_session_path)
  end
end
