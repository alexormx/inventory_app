# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Preorders::PreorderAllocator do
  let(:product) { create(:product, skip_seed_inventory: true, preorder_available: true) }
  let(:order) { create(:sale_order) }
  let(:line) do
    create(
      :sale_order_item,
      sale_order: order,
      product: product,
      quantity: 2,
      preorder_quantity: 2,
      unit_cost: 40,
      unit_selling_price: 100,
      unit_final_price: 100,
      total_line_cost: 200
    )
  end
  let(:location) { create(:inventory_location) }

  it 'allocates to the original line without increasing the purchased quantity' do
    reservation = create(
      :preorder_reservation,
      product: product,
      user: order.user,
      sale_order: order,
      sale_order_item: line,
      quantity: 1
    )
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(status: Inventory.statuses[:available], inventory_location_id: location.id)

    described_class.new(product, newly_available_units: 1).call

    expect(line.reload.quantity).to eq(2)
    expect(line.preorder_quantity).to eq(1)
    expect(inventory.reload.sale_order).to eq(order)
    expect(inventory.sale_order_item).to eq(line)
    expect(inventory.status).to eq('reserved')
    expect(reservation.reload).to be_assigned
  end

  it 'propagates unexpected batch allocation failures' do
    allow(described_class).to receive(:new).with(product).and_return(instance_double(described_class, call: nil))
    allow(described_class.new(product)).to receive(:call).and_raise(StandardError, 'allocation failed')

    expect { described_class.batch_allocate([product.id]) }
      .to raise_error(StandardError, 'allocation failed')
  end

  it 'serializes concurrent callbacks without losing or duplicating quantity' do
    reservation = create(
      :preorder_reservation,
      product: product,
      user: order.user,
      sale_order: order,
      sale_order_item: line,
      quantity: 2
    )
    supply = create_list(:inventory, 2, product: product, status: :damaged)
    Inventory.where(id: supply).update_all(status: Inventory.statuses[:in_transit])
    outcomes = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          outcomes << described_class.new(product.reload, newly_available_units: 1).call
        end
      end
    end
    threads.each(&:join)

    expect(2.times.sum { outcomes.pop }).to eq(2)
    expect(reservation.reload).to be_assigned
    expect(PreorderReservation.pending.where(sale_order_item: line).sum(:quantity)).to eq(0)
    expect(line.reload.preorder_quantity).to eq(0)
    expect(line.inventory_units.distinct.count).to eq(2)
    expect(PreorderReservation.where(sale_order_item: line).sum(:quantity)).to eq(2)
  end
end
