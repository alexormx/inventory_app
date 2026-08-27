# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Preorder supply reconciliation', type: :service do
  let(:product) do
    create(
      :product,
      skip_seed_inventory: true,
      preorder_available: true,
      backorder_allowed: false,
      status: 'active'
    )
  end
  let(:admin) { create(:user, :admin) }
  let(:location) { create(:inventory_location) }

  def preorder_commitment(quantity:, reserved_at: Time.current, condition: :brand_new)
    order = create(:sale_order)
    line = create(
      :sale_order_item,
      sale_order: order,
      product: product,
      item_condition: condition,
      quantity: quantity,
      preorder_quantity: quantity,
      unit_cost: 40,
      unit_selling_price: 100,
      unit_final_price: 100,
      total_line_cost: 100 * quantity
    )
    reservation = create(
      :preorder_reservation,
      product: product,
      user: order.user,
      sale_order: order,
      sale_order_item: line,
      quantity: quantity,
      reserved_at: reserved_at
    )
    [order, line, reservation]
  end

  def unlocated_stock(quantity, condition: :brand_new)
    create_list(
      :inventory,
      quantity,
      product: product,
      status: :available,
      item_condition: condition,
      inventory_location: nil
    )
  end

  def locate(quantity)
    Inventories::BulkAssignLocationService.call(
      product_id: product.id,
      quantity: quantity,
      location_id: location.id,
      actor: admin
    )
  end

  it 'gives an older pending preorder first claim on newly created inbound supply' do
    _order, line, reservation = preorder_commitment(quantity: 5, reserved_at: 2.days.ago)
    purchase_order = create(:purchase_order, status: 'In Transit')

    create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: 10)

    aggregate_failures do
      expect(reservation.reload).to be_assigned
      expect(line.reload.preorder_quantity).to eq(0)
      expect(line.inventory_units.where(status: :pre_reserved).count).to eq(5)
      expect(Inventory.customer_in_transit.where(product: product).count).to eq(5)
      expect(PreorderReservation.pending.where(product: product).sum(:quantity)).to eq(0)
    end
  end

  it 'keeps available unlocated inventory non-public' do
    inventory = unlocated_stock(1).first

    expect(Inventory.customer_on_hand).not_to include(inventory)
    expect(Inventory.customer_sellable).not_to include(inventory)
    expect(Product.publishable).not_to include(product)
  end

  it 'reconciles committed demand before located stock becomes public' do
    _order, line, reservation = preorder_commitment(quantity: 3, reserved_at: 2.days.ago)
    unlocated_stock(5)

    locate(5)

    aggregate_failures do
      expect(reservation.reload).to be_assigned
      expect(PreorderReservation.pending.where(product: product).sum(:quantity)).to eq(0)
      expect(line.reload.inventory_units.where(status: :reserved).count).to eq(3)
      expect(Inventory.customer_on_hand.where(product: product).count).to eq(2)
      expect(Inventory.customer_sellable.where(product: product).count).to eq(2)
    end
  end

  it 'leaves the exact pending remainder when located supply is smaller than demand' do
    _order, line, _reservation = preorder_commitment(quantity: 5, reserved_at: 2.days.ago)
    unlocated_stock(2)

    locate(2)

    aggregate_failures do
      expect(line.reload.inventory_units.where(status: :reserved).count).to eq(2)
      expect(line.preorder_quantity).to eq(3)
      expect(PreorderReservation.pending.where(product: product).sum(:quantity)).to eq(3)
      expect(Inventory.customer_sellable.where(product: product)).to be_empty
    end
  end

  it 'preserves FIFO across multiple preorder commitments' do
    _order_a, line_a, reservation_a = preorder_commitment(quantity: 2, reserved_at: 3.days.ago)
    _order_b, line_b, _reservation_b = preorder_commitment(quantity: 3, reserved_at: 2.days.ago)
    unlocated_stock(3)

    locate(3)

    aggregate_failures do
      expect(reservation_a.reload).to be_assigned
      expect(line_a.reload.inventory_units.where(status: :reserved).count).to eq(2)
      expect(line_a.preorder_quantity).to eq(0)
      expect(line_b.reload.inventory_units.where(status: :reserved).count).to eq(1)
      expect(line_b.preorder_quantity).to eq(2)
      expect(PreorderReservation.pending.where(sale_order_item: line_b).sum(:quantity)).to eq(2)
    end
  end

  it 'does not use another item condition to back a brand-new preorder' do
    _order, line, _reservation = preorder_commitment(quantity: 3, condition: :brand_new)
    unlocated_stock(2, condition: :mint)
    unlocated_stock(3, condition: :brand_new)

    locate(5)

    aggregate_failures do
      expect(line.reload.inventory_units.pluck(:item_condition).uniq).to eq(['brand_new'])
      expect(line.inventory_units.count).to eq(3)
      expect(Inventory.customer_sellable.where(product: product, item_condition: :mint).count).to eq(2)
      expect(Inventory.customer_sellable.where(product: product, item_condition: :brand_new)).to be_empty
    end
  end

  it 'rolls back location and audit rows when reconciliation fails' do
    preorder_commitment(quantity: 1)
    inventory = unlocated_stock(1).first
    allow(Preorders::PreorderAllocator).to receive(:new).and_raise(StandardError, 'reconciliation failed')

    expect { locate(1) }.to raise_error(StandardError, 'reconciliation failed')

    expect(inventory.reload.inventory_location_id).to be_nil
    expect(Inventory.customer_sellable.where(id: inventory.id)).to be_empty
    expect(InventoryEvent.where(inventory_id: inventory.id)).to be_empty
  end

  it 'preserves exact commitment quantity without duplicate pending artifacts' do
    _order, line, _reservation = preorder_commitment(quantity: 5, reserved_at: 2.days.ago)
    unlocated_stock(2)

    locate(2)

    reservations = PreorderReservation.where(sale_order_item: line)
    aggregate_failures do
      expect(reservations.assigned.sum(:quantity)).to eq(2)
      expect(reservations.pending.sum(:quantity)).to eq(3)
      expect(reservations.where(status: :pending).count).to eq(1)
      expect(reservations.sum(:quantity)).to eq(5)
      expect(line.reload.inventory_units.distinct.count).to eq(2)
    end
  end

  it 'derives its operational metrics from canonical inventory and reservation rows' do
    _order, _line, _reservation = preorder_commitment(quantity: 4)
    inbound_free = create_list(:inventory, 2, product: product, status: :damaged)
    inbound_committed = create_list(:inventory, 3, product: product, status: :damaged)
    unlocated_free = create(:inventory, product: product, status: :damaged)
    unlocated_reserved = create(:inventory, product: product, status: :damaged)
    located_free = create(:inventory, product: product, status: :damaged)
    located_reserved = create(:inventory, product: product, status: :damaged)
    order = create(:sale_order)
    line = create(:sale_order_item, sale_order: order, product: product)

    Inventory.where(id: inbound_free).update_all(status: Inventory.statuses[:in_transit])
    Inventory.where(id: inbound_committed).update_all(
      status: Inventory.statuses[:pre_reserved], sale_order_id: order.id, sale_order_item_id: line.id
    )
    unlocated_free.update_columns(status: Inventory.statuses[:available], inventory_location_id: nil)
    unlocated_reserved.update_columns(
      status: Inventory.statuses[:reserved], inventory_location_id: nil,
      sale_order_id: order.id, sale_order_item_id: line.id
    )
    located_free.update_columns(
      status: Inventory.statuses[:available], inventory_location_id: location.id,
      sale_order_id: nil, sale_order_item_id: nil
    )
    located_reserved.update_columns(
      status: Inventory.statuses[:reserved], inventory_location_id: location.id,
      sale_order_id: order.id, sale_order_item_id: line.id
    )

    summary = Preorders::CommitmentSummary.new(product).call

    expect(summary.to_h).to include(
      in_transit_total: 5,
      inbound_committed: 3,
      inbound_free: 2,
      pending_preorder: 4,
      received_unlocated_reserved: 1,
      received_unlocated_free: 1,
      located_reserved: 1,
      physical_free_on_hand: 1,
      true_free_sellable: 3,
      unbacked_demand: 4
    )
  end
end
