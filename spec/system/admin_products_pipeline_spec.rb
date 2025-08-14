require 'rails_helper'

RSpec.describe 'Admin products pipeline (system)', type: :system, js: true do
  let(:admin) { create(:user, :admin) }
  include Warden::Test::Helpers

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
  end

  it 'navega por tabs y activa un producto desde Drafts sin recargar toda la página' do
  Product.delete_all
  create_list(:product, 2, status: 'draft')
  create(:product, status: 'inactive')

  # Ir directo a la pestaña Drafts
  visit admin_products_drafts_path
    expect(page).to have_css('turbo-frame#products_frame')
    expect(page).to have_content('Total Draft')

    # Leer total inicial de Drafts y hacer clic en Activar
    initial_text = within('turbo-frame#products_frame') do
      find('span.badge.bg-secondary', text: /Total Draft:/).text
    end
    initial = initial_text[/Total Draft:\s*(\d+)/, 1].to_i

    within('turbo-frame#products_frame') do
      click_link('Activar', match: :first)
    end

    # Esperar a que se reemplace el frame y verificar el nuevo total
    expect(page).to have_css('turbo-frame#products_frame')
    within('turbo-frame#products_frame') do
      expect(page).to have_selector('span.badge.bg-secondary', text: /Total Draft:\s*#{initial - 1}/)
    end

    # Activar el primer producto
    within('turbo-frame#products_frame') do
      btn = first('a.btn.btn-sm.btn-primary', text: 'Activar', minimum: 1)
      btn.click if btn
    end

    # El frame debe seguir presente
  expect(page).to have_css('turbo-frame#products_frame')
  end
end
