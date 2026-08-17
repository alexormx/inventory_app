require 'rails_helper'

RSpec.describe 'Admin products pagination (system)', type: :system, js: true do
  let(:admin) { create(:user, :admin) }
  include Warden::Test::Helpers

  before do
    driven_by :selenium_chrome_headless
  end

  # El tamaño de página lo manda el controlador (PER_PAGE, una rejilla de 3x3).
  # El spec lo lee de ahí en vez de repetir el número: cuando se escribió esperaba
  # 12 —el valor que anunciaba el mensaje del commit— mientras el código siempre
  # sirvió 9, y el desfase pasó desapercibido porque la suite completa no corre en CI.
  let(:per_page) { Admin::ProductsController::PER_PAGE }
  let(:total_drafts) { per_page + 3 }

  it 'muestra una página completa de cards y navega a la página 2 en Drafts' do
  # Asegura un estado limpio de datos visibles
  Product.delete_all
  create_list(:product, total_drafts, status: 'draft')

  # login directo (Warden) para estabilidad
  login_as(admin, scope: :user)

    visit admin_products_drafts_path

    within('turbo-frame#products_frame') do
      expect(page).to have_css('.product-card', count: per_page)
      # Esperar barra de paginación y avanzar a página 2.
      # Kaminari marca con rel="next" tanto el número de la página siguiente
      # como la flecha "Next", así que hay dos enlaces equivalentes: tomamos el
      # primero en lugar de find, que aborta por coincidencia ambigua.
      expect(page).to have_css('.pagination')
      if page.has_css?(".pagination a[rel='next']")
        first(".pagination a[rel='next']").click
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
      expect(page).to have_css('.product-card', count: total_drafts - per_page)
    end
  end
end
