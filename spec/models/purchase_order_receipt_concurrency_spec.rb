# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Purchase order receipt and location assignment under concurrency', type: :model do
  self.use_transactional_tests = false

  RECEIPT_TABLES_TO_CLEAN = %w[
    inventory_events
    location_assignment_draft_lines
    location_assignment_drafts
    inventories
    preorder_reservations
    sale_order_items
    sale_orders
    purchase_order_items
    purchase_orders
    inventory_locations
    products
    users
  ].freeze

  def truncate_all!
    ActiveRecord::Base.connection.execute(
      "TRUNCATE TABLE #{RECEIPT_TABLES_TO_CLEAN.join(', ')} RESTART IDENTITY CASCADE"
    )
  end

  def run_in_parallel(count)
    barrier = Queue.new
    errors = Queue.new
    results = Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.pop
          results << yield(index)
        rescue StandardError => e
          errors << e
        end
      end
    end
    count.times { barrier << true }
    threads.each(&:join)

    collected_results = []
    collected_results << results.pop until results.empty?
    collected_errors = []
    collected_errors << errors.pop until errors.empty?
    [collected_results, collected_errors]
  end

  def receive_purchase_order(purchase_order)
    record = PurchaseOrder.find(purchase_order.id)
    record.with_lock do
      next false unless record.status == 'In Transit'

      record.update!(status: 'Delivered')
      true
    end
  end

  before { truncate_all! }
  after { truncate_all! }

  let!(:admin) { create(:user, :admin) }
  let!(:product) do
    create(:product, skip_seed_inventory: true, status: 'active',
                     preorder_available: true, backorder_allowed: false)
  end
  let!(:warehouse) { create(:inventory_location, :warehouse) }
  let!(:location_a) { create(:inventory_location, :shelf, parent: warehouse) }
  let!(:location_b) { create(:inventory_location, :shelf, parent: warehouse) }

  it 'serializes receipt against physical assignment without exposing inbound rows as assignable' do
    purchase_order = create(:purchase_order, status: 'In Transit')
    item = create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: 6)

    results, errors = run_in_parallel(2) do |index|
      if index.zero?
        receive_purchase_order(purchase_order)
      else
        Inventories::BulkAssignLocationService.call(
          product_id: product.id,
          quantity: 4,
          location_id: location_a.id,
          actor: admin
        )
      end
    end

    expected_shortage = errors.select do |error|
      error.is_a?(Inventories::BulkAssignLocationService::InsufficientEligibleInventory)
    end
    unexpected = errors - expected_shortage
    units = Inventory.where(purchase_order_item: item)
    located = units.where(inventory_location: location_a)

    aggregate_failures do
      expect(unexpected).to be_empty
      expect(expected_shortage.size).to be <= 1
      expect(results).to include(true)
      expect(purchase_order.reload.status).to eq('Delivered')
      expect(units.where(status: :available).count).to eq(6)
      expect(units.where(status: %i[in_transit pre_reserved]).count).to eq(0)
      expect([0, 4]).to include(located.count)
      expect(InventoryEvent.where(inventory_id: units, event_type: 'physical_inventory_verification').count)
        .to eq(located.count)
    end
  end

  it 'preserves inbound preorder commitments when receipt races reconciliation' do
    sale_order = create(:sale_order)
    sale_order_item = create(
      :sale_order_item,
      sale_order: sale_order,
      product: product,
      quantity: 3,
      preorder_quantity: 3,
      unit_selling_price: 100,
      unit_final_price: 100
    )
    reservation = create(
      :preorder_reservation,
      product: product,
      user: sale_order.user,
      sale_order: sale_order,
      sale_order_item: sale_order_item,
      quantity: 3,
      reserved_at: 2.days.ago
    )
    purchase_order = create(:purchase_order, status: 'In Transit')
    item = create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: 10)

    _results, errors = run_in_parallel(2) do |index|
      index.zero? ? receive_purchase_order(purchase_order) : Preorders::PreorderAllocator.new(product).call
    end

    units = Inventory.where(purchase_order_item: item)
    committed = units.where(sale_order_item: sale_order_item)

    aggregate_failures do
      expect(errors).to be_empty
      expect(purchase_order.reload.status).to eq('Delivered')
      expect(committed.where(status: :reserved).count).to eq(3)
      expect(committed.pluck(:sale_order_id).uniq).to eq([sale_order.id])
      expect(committed.pluck(:sale_order_item_id).uniq).to eq([sale_order_item.id])
      expect(units.where(status: :available, sale_order_id: nil).count).to eq(7)
      expect(reservation.reload).to be_assigned
    end
  end

  it 'allows only one competing assignment batch to consume the same FIFO rows' do
    purchase_order = create(:purchase_order, status: 'Delivered')
    item = create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: 6)

    _results, errors = run_in_parallel(2) do |index|
      Inventories::BulkAssignLocationService.call(
        product_id: product.id,
        quantity: 4,
        location_id: index.zero? ? location_a.id : location_b.id,
        actor: admin
      )
    end

    expected_shortages = errors.select do |error|
      error.is_a?(Inventories::BulkAssignLocationService::InsufficientEligibleInventory)
    end
    units = Inventory.where(purchase_order_item: item)
    events = InventoryEvent.where(inventory_id: units, event_type: 'physical_inventory_verification')

    aggregate_failures do
      expect(errors.size).to eq(1)
      expect(expected_shortages.size).to eq(1)
      expect(units.where.not(inventory_location_id: nil).count).to eq(4)
      expect([units.where(inventory_location: location_a).count,
              units.where(inventory_location: location_b).count]).to match_array([0, 4])
      expect(events.count).to eq(4)
      expect(events.distinct.count(:inventory_id)).to eq(4)
    end
  end
end
