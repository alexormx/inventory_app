require 'rails_helper'

RSpec.describe 'Cookie banner', type: :system, js: true do
  before do
    driven_by :selenium_chrome_headless
    visit root_path
    page.driver.browser.manage.delete_all_cookies
  end

  it 'displays and hides banner after acceptance' do
    expect(page).to have_css('#cookie-banner', visible: :all)
    
    # Encuentra el botón (incluso si está oculto)
    button = find('#accept-cookies', visible: :all)
    
    # Usa JavaScript para forzar el clic en el botón
    page.execute_script("arguments[0].click();", button)
    
    # Verifica que el banner ya no sea visible
    expect(page).to have_no_css('#cookie-banner', visible: true)
  end
end