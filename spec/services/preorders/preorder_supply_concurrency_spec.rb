# frozen_string_literal: true

require 'rails_helper'

# Real concurrency proof.
#
# The default suite runs with transactional fixtures, which pins a single
# connection across threads: `SELECT ... FOR UPDATE` can never block itself, so
# those examples cannot prove serialization. These examples opt out so every
# thread gets its own connection and Postgres row locks actually contend.
RSpec.describe 'Preorder supply reconciliation under concurrency', type: :service do
  self.use_transactional_tests = false

  TABLES_TO_CLEAN = %w[
    inventory_events
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
      "TRUNCATE TABLE #{TABLES_TO_CLEAN.join(', ')} RESTART IDENTITY CASCADE"
    )
  end

  before { truncate_all! }
  after  { truncate_all! }

  let!(:product) do
    create(
      :product,
      skip_seed_inventory: true,
      preorder_available: true,
      backorder_allowed: false,
      status: 'active'
    )
  end

  def preorder_demand(quantity:, reserved_at: Time.current)
    order = create(:sale_order)
    line = create(
      :sale_order_item,
      sale_order: order,
      product: product,
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

  # Runs blocks in parallel, each on its own connection, released together so
  # they genuinely overlap. Re-raises anything a thread saw.
  def run_in_parallel(count)
    barrier = Queue.new
    errors = Queue.new
    threads = count.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.pop
          begin
            yield i
          rescue StandardError => e
            errors << e
          end
        end
      end
    end
    sleep 0.05
    count.times { barrier << true }
    threads.each(&:join)
    raise errors.pop until errors.empty?
  end

  def backed_inbound
    Inventory.where(product_id: product.id, status: :pre_reserved).count
  end

  def free_inbound
    Inventory.customer_in_transit.where(product_id: product.id).count
  end

  def pending_demand
    PreorderReservation.pending.where(product_id: product.id).sum(:quantity).to_i
  end

  it 'serializes parallel allocators over fixed supply without double-allocating' do
    _order, line, _reservation = preorder_demand(quantity: 3, reserved_at: 2.days.ago)
    supply = create_list(:inventory, 5, product: product, status: :damaged)
    Inventory.where(id: supply).update_all(status: Inventory.statuses[:in_transit])

    run_in_parallel(4) { Preorders::PreorderAllocator.new(product).call }

    aggregate_failures do
      expect(backed_inbound).to eq(3)
      expect(free_inbound).to eq(2)
      expect(pending_demand).to eq(0)
      # Exactly the committed quantity, assigned exactly once.
      expect(line.reload.inventory_units.distinct.count).to eq(3)
      expect(PreorderReservation.where(sale_order_item: line).sum(:quantity)).to eq(3)
    end
  end

  it 'keeps older demand whole when several purchase orders land at once' do
    _order, line, _reservation = preorder_demand(quantity: 6, reserved_at: 2.days.ago)

    # Purchase orders are created up front: their custom-id generator is a
    # check-then-insert and races on its own, which is a separate pre-existing
    # concern. The contention under test is the supply that item creation makes.
    purchase_orders = Array.new(2) { create(:purchase_order, status: 'In Transit') }

    run_in_parallel(2) do |i|
      create(:purchase_order_item, purchase_order: purchase_orders[i], product: product, quantity: 5)
    end

    aggregate_failures do
      expect(Inventory.where(product_id: product.id).count).to eq(10)
      expect(backed_inbound).to eq(6)
      expect(free_inbound).to eq(4)
      expect(pending_demand).to eq(0)
      expect(line.reload.inventory_units.distinct.count).to eq(6)
      expect(PreorderReservation.where(sale_order_item: line).sum(:quantity)).to eq(6)
    end
  end

  it 'never frees located supply while older demand is still pending' do
    _order, line, _reservation = preorder_demand(quantity: 4, reserved_at: 2.days.ago)
    admin = create(:user, :admin)
    location = create(:inventory_location)
    unlocated = create_list(:inventory, 6, product: product, status: :available, inventory_location: nil)
    expect(unlocated.size).to eq(6)

    # One thread publishes stock by locating it; the others race to allocate.
    run_in_parallel(3) do |i|
      if i.zero?
        Inventories::BulkAssignLocationService.call(
          product_id: product.id, quantity: 6, location_id: location.id, actor: admin
        )
      else
        Preorders::PreorderAllocator.new(product).call
      end
    end

    aggregate_failures do
      # The invariant: free sellable stock is supply minus older committed demand.
      expect(line.reload.inventory_units.where(status: :reserved).count).to eq(4)
      expect(pending_demand).to eq(0)
      expect(Inventory.customer_sellable.where(product_id: product.id).count).to eq(2)
      expect(PreorderReservation.where(sale_order_item: line).sum(:quantity)).to eq(4)
    end
  end

  it 'preserves FIFO priority between two commitments under parallel supply' do
    _oa, line_a, res_a = preorder_demand(quantity: 4, reserved_at: 3.days.ago)
    _ob, line_b, _res_b = preorder_demand(quantity: 4, reserved_at: 1.day.ago)

    purchase_orders = Array.new(2) { create(:purchase_order, status: 'In Transit') }

    run_in_parallel(2) do |i|
      create(:purchase_order_item, purchase_order: purchase_orders[i], product: product, quantity: 3)
    end

    aggregate_failures do
      expect(Inventory.where(product_id: product.id).count).to eq(6)
      # The older commitment must be filled completely before the newer one.
      expect(line_a.reload.inventory_units.distinct.count).to eq(4)
      expect(res_a.reload).to be_assigned
      expect(line_b.reload.inventory_units.distinct.count).to eq(2)
      expect(backed_inbound).to eq(6)
      expect(free_inbound).to eq(0)
      expect(pending_demand).to eq(2)
    end
  end
end
