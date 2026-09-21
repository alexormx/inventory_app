# frozen_string_literal: true

require 'rails_helper'

# A NEW cart hold versus an UNRELATED sale-order reservation, racing for one
# physical unit that starts free and unheld.
#
# This is not the cart-versus-cart race: those two contend on the same
# cart_inventory_holds row and are serialized by UNIQUE(inventory_id). Here the
# two paths touch DIFFERENT tables - a hold writes cart_inventory_holds, a
# reservation writes inventories - so they only serialize if they share a lock
# on the physical row itself.
#
# Forbidden committed state:
#
#   inventories(#123)          -> reserved by an unrelated SaleOrder
#   cart_inventory_holds(#123) -> active, owned by a cart
RSpec.describe 'Cart hold versus unrelated reservation', type: :service do
  self.use_transactional_tests = false

  RACE_TABLES = %w[
    cart_inventory_holds shopping_cart_items shopping_carts
    inventory_events inventories preorder_reservations
    sale_order_items sale_orders purchase_order_items purchase_orders
    inventory_locations products users
  ].freeze

  def truncate_all!
    ActiveRecord::Base.connection.execute(
      "TRUNCATE TABLE #{RACE_TABLES.join(', ')} RESTART IDENTITY CASCADE"
    )
  end

  before { truncate_all! }
  after  { truncate_all! }

  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true, status: :active) }

  def unit
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(
      status: Inventory.statuses['available'],
      item_condition: Inventory.item_conditions['brand_new'],
      inventory_location_id: location.id
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

  # A line belonging to nobody's cart. Created while NO stock exists, so its
  # after_save reservation callback finds nothing and the reservation really
  # happens later, inside the race.
  def unrelated_line(for_product = product)
    order = create(:sale_order)
    line = SaleOrderItem.new(
      sale_order: order, product: for_product, quantity: 1,
      preorder_quantity: 0, backordered_quantity: 0, item_condition: :brand_new,
      unit_cost: 40, unit_selling_price: 100, unit_final_price: 100, total_line_cost: 40
    )
    line.save!
    raise 'fixture error: line reserved before the race' if line.inventory_units.any?

    line
  end

  def claim_hold(cart, item)
    Carts::HoldInventory.sync(
      cart: cart, cart_item: item, product: product,
      condition: :brand_new, target_quantity: 1
    )
  end

  def run_pair(first, second)
    errors = Queue.new
    threads = [first, second].map do |work|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { work.call }
      rescue StandardError => e
        errors << e
      end
    end
    threads.each { |t| t.join(20) }
    errors.close
    []
  end

  def assert_single_claimant!(inventory)
    inventory.reload
    reserved = inventory.sale_order_id.present?
    held = CartInventoryHold.active.where(inventory_id: inventory.id).exists?

    expect(reserved && held).to be(false),
                                "both committed against the same physical unit: " \
                                "reserved=#{reserved} active_hold=#{held}"
    expect(reserved || held).to be(true), 'neither claimant took the unit'
  end

  # Ordering A: the reservation takes its row lock first; the hold then races
  # while that transaction is still open.
  #
  # The hold's INSERT cannot slip past, because cart_inventory_holds.inventory_id
  # carries a foreign key to inventories, so inserting takes a KEY SHARE lock on
  # the very row the reservation holds. The hold blocks until the reservation
  # commits - and must then re-check eligibility rather than proceed blindly.
  #
  # The reservation does NOT wait for the hold here: making it do so would
  # deadlock the test itself, not the production code.
  it 'refuses a new hold on a unit an open reservation has already locked' do
    line = unrelated_line          # no stock yet
    inventory = unit               # stock appears afterwards
    cart, item = cart_with_item
    reserved_gate = Queue.new

    run_pair(
      lambda {
        ActiveRecord::Base.transaction do
          InventoryServices::ReserveSaleOrderItem.call(line, strict: false)
          reserved_gate << :locked          # row locked, transaction still open
          sleep 0.5                         # hold races during this window
        end                                 # commits here, unblocking the hold
      },
      lambda {
        reserved_gate.pop
        claim_hold(cart, item)
      }
    )

    assert_single_claimant!(inventory)
  end

  # Ordering B: the hold commits first, then an unrelated reservation races.
  it 'refuses a reservation of a unit a cart has just taken a hold on' do
    line = unrelated_line
    inventory = unit
    cart, item = cart_with_item
    hold_gate = Queue.new

    run_pair(
      lambda {
        ActiveRecord::Base.transaction do
          claim_hold(cart, item)
          hold_gate << :held                # hold taken, transaction still open
          sleep 0.5                         # reservation races during this window
        end
      },
      lambda {
        hold_gate.pop
        ActiveRecord::Base.transaction do
          InventoryServices::ReserveSaleOrderItem.call(line, strict: false)
        end
      }
    )

    assert_single_claimant!(inventory)
  end

  it 'keeps exactly one claimant when both start simultaneously, repeatedly' do
    5.times do
      # Fresh product per round rather than truncating, which would delete the
      # memoized fixtures this example still holds references to.
      fresh = create(:product, skip_seed_inventory: true, status: :active)
      line = unrelated_line(fresh)
      inventory = create(:inventory, product: fresh, status: :damaged)
      inventory.update_columns(
        status: Inventory.statuses['available'],
        item_condition: Inventory.item_conditions['brand_new'],
        inventory_location_id: location.id
      )
      inventory.reload
      cart = ShoppingCart.create!(user: create(:user), status: 'active', last_activity_at: Time.current)
      item = cart.shopping_cart_items.create!(
        product: fresh, product_reference: fresh.id,
        condition: :brand_new, quantity: 1, product_name_snapshot: fresh.product_name
      )

      run_pair(
        -> { ActiveRecord::Base.transaction { InventoryServices::ReserveSaleOrderItem.call(line, strict: false) } },
        lambda {
          Carts::HoldInventory.sync(cart: cart, cart_item: item, product: fresh,
                                    condition: :brand_new, target_quantity: 1)
        }
      )

      assert_single_claimant!(inventory)
    end
  end
end
