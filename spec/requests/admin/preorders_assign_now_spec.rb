# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin preorders assign_now', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:product) { create(:product, skip_seed_inventory: true, preorder_available: true) }

  before { sign_in admin }

  it 'reports units assigned from received stock, not only inbound pre-reservations' do
    order = create(:sale_order)
    line = create(:sale_order_item, sale_order: order, product: product, quantity: 1, preorder_quantity: 1,
                                    unit_final_price: 100)
    create(:preorder_reservation, product: product, user: order.user, sale_order: order,
                                  sale_order_item: line, quantity: 1)
    create(:inventory, product: product, status: :available, inventory_location: nil)

    post admin_preorders_assign_now_path

    expect(line.reload.inventory_units.where(status: :reserved).count).to eq(1)
    expect(flash[:notice]).to include('Unidades asignadas: 1.')
  end
end
