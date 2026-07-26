# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin cancels sale order', type: :system do
  let(:admin) { create(:user, role: 'admin') }
  let(:customer) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:sale_order) { create(:sale_order, user: customer, status: 'Pending') }
  let!(:inventory) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }

  before { sign_in admin }

  def cancel_from_page
    visit admin_sale_order_path(sale_order)
    find("form[action='#{cancel_admin_sale_order_path(sale_order)}'] button").click
    find('#global-confirm-modal.show [data-confirm="ok"]').click
  end

  it 'shows the simple cancel button for a pending unpaid order' do
    visit admin_sale_order_path(sale_order)

    expect(page).to have_css("form[action='#{cancel_admin_sale_order_path(sale_order)}']")
  end

  it 'does not show the cancel button for an already canceled order' do
    sale_order.update!(status: 'Canceled')
    visit admin_sale_order_path(sale_order)

    expect(page).not_to have_css("form[action='#{cancel_admin_sale_order_path(sale_order)}']")
  end

  it 'shows refund/return review instead of simple cancellation for a paid order' do
    create(:payment, sale_order: sale_order, amount: sale_order.total_order_value, status: 'Completed')
    visit admin_sale_order_path(sale_order.reload)

    expect(page).to have_content('Cancelación requiere revisión de pago/devolución')
  end

  it 'cancels a pending unpaid order and releases reserved inventory', :aggregate_failures, :js do
    cancel_from_page
    expect(page).to have_content('Orden cancelada')
    expect(page).to have_content('Orden Cancelada')
    expect(inventory.reload.status).to eq('available')
    expect(inventory.sale_order_id).to be_nil
  end
end
