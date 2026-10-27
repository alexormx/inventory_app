# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PurchaseOrder, 'destroy', type: :model do
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:purchase_order) { create(:purchase_order, status: 'Pending') }
  let!(:line) { create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: 3) }

  def pieces = Inventory.where(purchase_order_id: purchase_order.id)

  it 'removes a fresh order with its line and free pieces' do
    expect(purchase_order.destroy).to be_truthy

    expect(PurchaseOrderItem.where(id: line.id)).to be_empty
    expect(pieces).to be_empty
  end

  it 'refuses with a message instead of failing when a piece was retired by a quantity reduction' do
    line.update!(quantity: 2)

    expect(purchase_order.destroy).to be(false)
    expect(purchase_order.errors[:base].join).to include('Cancela')
    expect(PurchaseOrder.where(id: purchase_order.id)).to exist
  end

  it 'refuses with a message instead of failing when a piece has audit history' do
    InventoryEvent.create!(inventory: pieces.first, product_id: product.id, event_type: 'status_change', metadata: {})

    expect(purchase_order.destroy).to be(false)
    expect(purchase_order.errors[:base].join).to include('Cancela')
    expect(pieces.count).to eq(3)
  end

  it 'refuses while a piece is committed to a customer' do
    order = create(:sale_order)
    pieces.first.update_columns(status: Inventory.statuses[:pre_reserved], sale_order_id: order.id)

    expect(purchase_order.destroy).to be(false)
    expect(pieces.count).to eq(3)
  end
end

RSpec.describe PurchaseOrderItem, 'destroy', type: :model do
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:purchase_order) { create(:purchase_order, status: 'In Transit') }
  let!(:line) { create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: 2) }

  it 'takes its free pieces with it when the line is removed from the order' do
    purchase_order.update!(purchase_order_items_attributes: [{ id: line.id, _destroy: '1' }])

    expect(Inventory.where(product: product).where.not(status: :scrap)).to be_empty
    expect(Inventory.customer_sellable.where(product: product)).to be_empty
  end
end
