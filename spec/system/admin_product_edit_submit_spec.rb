require 'rails_helper'

RSpec.describe 'Admin product edit submit', type: :system, js: true do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let!(:product) { create(:product, product_name: 'Tomica Supra base', series: 'Serie inicial') }

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
  end

  it 'guarda cambios desde editar y navega al show del producto' do
    visit edit_admin_product_path(product)

    expect(page).to have_css("form[action='#{admin_product_path(product)}'] button[type='submit']", text: 'Guardar Producto')

    fill_in 'Nombre del Producto', with: 'Tomica Supra editado'
    fill_in 'Serie', with: 'Tomica Premium'
    click_button 'Guardar Producto'

    expect(page).to have_current_path(admin_product_path(product), ignore_query: true)
    expect(page).to have_content('Product updated successfully.')
    expect(page).to have_content('Tomica Supra editado')
  end
end
