# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin cancels sale order', type: :system do
  let(:admin) { create(:user, role: 'admin') }
  let(:customer) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let!(:inventory1) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }
  let!(:inventory2) { create(:inventory, product: product, status: :sold, sale_order: sale_order) }
  let(:sale_order) { create(:sale_order, user: customer, status: 'Confirmed') }

  before do
    sign_in admin
  end

  it 'shows cancel button for non-canceled orders' do
    visit admin_sale_order_path(sale_order)

    expect(page).to have_button('Cancel Order')
  end

  it 'does not show cancel button for already canceled orders' do
    sale_order.update!(status: 'Canceled')
    visit admin_sale_order_path(sale_order)

    expect(page).not_to have_button('Cancel Order')
  end

  it 'cancels the order and releases inventories', js: true do
    visit admin_sale_order_path(sale_order)

    # Aceptar el diálogo de confirmación
    accept_confirm do
      click_button 'Cancel Order'
    end

    expect(page).to have_content('Orden cancelada exitosamente')
    expect(page).to have_content('Canceled') # Status badge

    # Verificar que los inventories fueron liberados
    expect(inventory1.reload.status).to eq('available')
    expect(inventory1.sale_order_id).to be_nil
    expect(inventory2.reload.status).to eq('available')
    expect(inventory2.sale_order_id).to be_nil
  end
end
