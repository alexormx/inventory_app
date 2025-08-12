require 'rails_helper'

RSpec.describe 'Cookie banner', type: :system, js: true do
  before do
    driven_by :selenium_chrome_headless
    Capybara.reset_sessions!  # clears cookies for current session regardless of driver
    # make sure no consent is remembered
    visit root_path
    execute_script('localStorage.clear(); sessionStorage.clear();')
    visit root_path
  end

  it 'displays and hides banner after acceptance' do
    expect(page).to have_css('#cookie-banner', visible: :all, wait: 5)
    click_button 'Accept'
    expect(page).to have_no_css('#cookie-banner', wait: 5)
  end
end