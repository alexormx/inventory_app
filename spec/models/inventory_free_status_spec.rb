require 'rails_helper'

RSpec.describe Inventory, type: :model do
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:sale_order) { create(:sale_order) }
  let(:sale_order_item) { create(:sale_order_item, sale_order: sale_order, product: product, quantity: 1) }

  it 'clears sale_order links when status changes to available' do
  inv = Inventory.create!(product: product, purchase_cost: 10, status: :reserved, sale_order_id: sale_order.id, sale_order_item_id: sale_order_item.id, sold_price: 55.5)
    expect(inv.sale_order_id).to eq(sale_order.id)
    inv.update!(status: :available)
    inv.reload
    expect(inv.status).to eq('available')
    expect(inv.sale_order_id).to be_nil
  expect(inv.sale_order_item_id).to be_nil
  expect(inv.sold_price).to be_nil
  end

  it 'clears sale_order links when status changes to in_transit' do
  inv = Inventory.create!(product: product, purchase_cost: 10, status: :reserved, sale_order_id: sale_order.id, sale_order_item_id: sale_order_item.id, sold_price: 70)
    inv.update!(status: :in_transit)
    inv.reload
    expect(inv.status).to eq('in_transit')
    expect(inv.sale_order_id).to be_nil
  expect(inv.sale_order_item_id).to be_nil
  expect(inv.sold_price).to be_nil
  end
end
