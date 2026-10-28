# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin favorites', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:wanted) { create(:product, skip_seed_inventory: true, product_name: 'Muy guardado') }
  let(:less_wanted) { create(:product, skip_seed_inventory: true, product_name: 'Poco guardado') }

  before do
    sign_in admin
    3.times { Favorite.save_for(create(:user), wanted) }
    Favorite.save_for(create(:user), wanted, source: 'abandoned_cart')
    Favorite.save_for(create(:user), less_wanted)
  end

  it 'ranks products by how many customers have them saved' do
    get admin_favorites_path

    expect(response).to have_http_status(:ok)
    expect(response.body.index('Muy guardado')).to be < response.body.index('Poco guardado')
  end

  it 'counts customers that saved it and then bought it' do
    buyer = create(:user)
    Favorite.save_for(buyer, wanted)
    create(:sale_order_item, sale_order: create(:sale_order, user: buyer), product: wanted)

    get admin_favorites_path

    expect(response.body).to include('data-purchased="1"')
  end

  it 'can show only the products without stock' do
    located = create(:inventory_location)
    piece = create(:inventory, product: less_wanted, status: :damaged)
    piece.update_columns(status: Inventory.statuses[:available], inventory_location_id: located.id)

    get admin_favorites_path(without_stock: '1')

    expect(response.body).to include('Muy guardado')
    expect(response.body).not_to include('Poco guardado')
  end

  it 'lists the customers who saved a product' do
    customer = create(:user, name: 'Ana Coleccionista')
    Favorite.save_for(customer, wanted)

    get admin_favorite_path(wanted.id)

    expect(response.body).to include('Ana Coleccionista')
  end

  it 'is only for admins' do
    sign_in create(:user)

    get admin_favorites_path

    expect(response).not_to have_http_status(:ok)
  end
end
