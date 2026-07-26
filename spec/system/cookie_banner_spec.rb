# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Cookie banner', :js, type: :system do
  before do
    driven_by :selenium_chrome_headless
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    page.execute_script('localStorage.clear(); sessionStorage.clear();')
    visit root_path
  end

  it 'is visible before the visitor decides' do
    expect(page).to have_css('#cookie-banner', visible: true)
  end

  it 'hides after acceptance' do
    click_button 'Aceptar'

    expect(page).to have_no_css('#cookie-banner', visible: :all)
  end

  it 'stays hidden after acceptance and reload' do
    click_button 'Aceptar'
    refresh

    expect(page).to have_no_css('#cookie-banner', visible: :all)
  end
end
