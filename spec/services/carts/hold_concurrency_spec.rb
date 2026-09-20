# frozen_string_literal: true

require 'rails_helper'

# Competition for one physical unit is resolved by PostgreSQL, so these run
# against real concurrent connections rather than a transactional fixture.
# Transactional fixtures pin one connection across threads, so FOR UPDATE can
# never contend with itself. These examples opt out, following the same pattern
# as spec/services/preorders/preorder_supply_concurrency_spec.rb, and truncate
# before AND after so nothing leaks into the rest of the suite.
RSpec.describe 'Cart inventory hold concurrency', type: :service do
  self.use_transactional_tests = false

  HOLD_TABLES_TO_CLEAN = %w[
    cart_inventory_holds
    shopping_cart_items
    shopping_carts
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
      "TRUNCATE TABLE #{HOLD_TABLES_TO_CLEAN.join(', ')} RESTART IDENTITY CASCADE"
    )
  end

  before { truncate_all! }
  after  { truncate_all! }

  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true, status: :active) }

  def unit(condition: :brand_new, status: :available)
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(
      status: Inventory.statuses[status.to_s],
      item_condition: Inventory.item_conditions[condition.to_s],
      inventory_location_id: (status == :available ? location.id : nil)
    )
    inventory.reload
  end

  def cart_with_item
    cart = ShoppingCart.create!(user: create(:user), status: 'active', last_activity_at: Time.current)
    item = cart.shopping_cart_items.create!(
      product: product, product_reference: product.id,
      condition: :brand_new, quantity: 1, product_name_snapshot: product.product_name
    )
    [cart, item]
  end

  def claim(cart, item)
    Carts::HoldInventory.sync(
      cart: cart, cart_item: item, product: product,
      condition: :brand_new, target_quantity: 1
    )
  end

  def in_parallel(count, &block)
    results = Queue.new
    threads = Array.new(count) do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { results << block.call(index) }
      rescue StandardError => e
        results << e
      end
    end
    threads.each(&:join)
    Array.new(count) { results.pop }
  end

  # Race A - two carts, one physical unit.
  it 'gives one physical unit to exactly one of two racing carts' do
    unit
    carts = Array.new(2) { cart_with_item }

    outcomes = in_parallel(2) { |i| claim(carts[i][0], carts[i][1]).held }

    expect(outcomes.sum).to eq(1)
    expect(CartInventoryHold.count).to eq(1)
    expect(CartInventoryHold.active.count).to eq(1)
  end

  # Thread count stays inside the connection pool; the point is contention for
  # scarce units, not pool exhaustion.
  it 'never double-claims when more carts race than there are units' do
    2.times { unit }
    carts = Array.new(4) { cart_with_item }

    outcomes = in_parallel(4) { |i| claim(carts[i][0], carts[i][1]).held }

    expect(outcomes.sum).to eq(2)
    expect(CartInventoryHold.count).to eq(2)
    expect(CartInventoryHold.pluck(:inventory_id).uniq.size).to eq(2)
  end

  # Race B - cart hold versus PreorderAllocator.
  it 'keeps a held unit away from the preorder allocator' do
    held_unit = unit
    cart, item = cart_with_item
    expect(claim(cart, item).held).to eq(1)

    order = create(:sale_order)
    line = create(:sale_order_item, sale_order: order, product: product, quantity: 1,
                                    preorder_quantity: 1, item_condition: :brand_new,
                                    unit_cost: 40, unit_selling_price: 100,
                                    unit_final_price: 100, total_line_cost: 40)
    reservation = create(:preorder_reservation, product: product, user: order.user,
                                                sale_order: order, sale_order_item: line, quantity: 1)

    in_parallel(2) do |i|
      i.zero? ? Preorders::PreorderAllocator.new(product).call : nil
    end

    expect(reservation.reload).to be_pending
    expect(held_unit.reload.sale_order_item_id).to be_nil
    expect(CartInventoryHold.active.count).to eq(1)
  end

  # Race D - an expired hold is reclaimable.
  it 'lets a rival cart atomically reclaim an expired hold' do
    unit
    cart_a, item_a = cart_with_item
    claim(cart_a, item_a)
    CartInventoryHold.update_all(expires_at: 1.second.ago)
    cart_b, item_b = cart_with_item

    expect(claim(cart_b, item_b).held).to eq(1)
    expect(CartInventoryHold.count).to eq(1)
    expect(CartInventoryHold.first.shopping_cart_id).to eq(cart_b.id)
  end

  # Race E - two carts racing to reclaim the SAME expired hold.
  it 'produces exactly one owner when two carts race to reclaim one expired hold' do
    unit
    cart_a, item_a = cart_with_item
    claim(cart_a, item_a)
    CartInventoryHold.update_all(expires_at: 1.second.ago)
    rivals = Array.new(2) { cart_with_item }

    outcomes = in_parallel(2) { |i| claim(rivals[i][0], rivals[i][1]).held }

    expect(outcomes.sum).to eq(1)
    expect(CartInventoryHold.count).to eq(1)
    owner = CartInventoryHold.first.shopping_cart_id
    expect(owner).to be_in(rivals.map { |c| c[0].id })
  end
end
