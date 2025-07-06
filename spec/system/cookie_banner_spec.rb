require 'rails_helper'

RSpec.describe 'Cookie banner', type: :system, js: true do
  it 'displays and hides banner after acceptance' do
    visit root_path
    expect(page).to have_selector('#cookie-banner', visible: true)
    click_button 'Aceptar'
    expect(page).not_to have_selector('#cookie-banner', visible: true)
  end
end