# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Favorites list', type: :system do
  it 'removes a product from the list and updates the navbar count without reloading', js: true do
    user = create(:user, name: 'Ana Cliente')
    product = create(:product, skip_seed_inventory: true, product_name: 'Tomica 2000GT', selling_price: 189)
    Favorite.save_for(user, product)

    visit new_user_session_path
    accept_cookies_if_present
    fill_in 'user[email]', with: user.email
    fill_in 'user[password]', with: 'password123'
    click_button 'Iniciar sesión'
    expect(page).to have_content('Sesión iniciada.')

    visit favorites_path
    expect(page).to have_css('#favorites-count', text: '1')

    find("#favorite_heart_#{product.id} button").click

    expect(page).to have_no_css("#favorite_row_#{product.id}")
    expect(page).to have_css('#favorites-count.d-none', visible: :all)
    expect(Favorite.open.count).to eq(0)
  end
end
