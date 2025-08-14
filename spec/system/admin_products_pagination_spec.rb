require 'rails_helper'

RSpec.describe 'Admin products pagination (system)', type: :system, js: true do
  let(:admin) { create(:user, :admin) }
  include Warden::Test::Helpers

  before do
    driven_by :selenium_chrome_headless
  end

  it 'muestra 12 cards por página y navega a la página 2 en Drafts' do
  # Asegura un estado limpio de datos visibles
  Product.delete_all
  create_list(:product, 15, status: 'draft')

  # login directo (Warden) para estabilidad
  login_as(admin, scope: :user)

    visit admin_products_drafts_path

    within('turbo-frame#products_frame') do
      expect(page).to have_css('.product-card', count: 12)
      # Esperar barra de paginación y avanzar a página 2
      expect(page).to have_css('.pagination')
      if page.has_css?(".pagination a[rel='next']")
        find(".pagination a[rel='next']").click
      else
        # Fallback: enlace explícito a page=2 o etiqueta Next/Siguiente
        if page.has_link?("2")
          click_link("2")
        else
          click_link(/Next|Siguiente/i)
        end
      end
    end

    within('turbo-frame#products_frame') do
      expect(page).to have_css('.product-card', count: 3)
    end
  end
end
