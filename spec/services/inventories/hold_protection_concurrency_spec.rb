# frozen_string_literal: true

require 'rails_helper'

# Admin protection versus live cart activity, on real connections.
#
# Both sides serialize on the physical Inventory row: Carts::HoldInventory
# locks it before claiming, and Inventories::HoldProtection locks it before
# mutating. Neither takes Product or ShoppingCart, so the admin guard adds no
# new edge to the lock hierarchy established by PR #184.
RSpec.describe 'Admin hold protection under concurrency', type: :service do
  self.use_transactional_tests = false

  ADMIN_RACE_TABLES = %w[
    cart_inventory_holds shopping_cart_items shopping_carts
    inventory_events inventories preorder_reservations
    sale_order_items sale_orders purchase_order_items purchase_orders
    inventory_locations products users
  ].freeze

  def truncate_all!
    ActiveRecord::Base.connection.execute(
      "TRUNCATE TABLE #{ADMIN_RACE_TABLES.join(', ')} RESTART IDENTITY CASCADE"
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

  def claim_hold(cart, item)
    Carts::HoldInventory.sync(
      cart: cart, cart_item: item, product: product,
      condition: :brand_new, target_quantity: 1
    )
  end

  # Mirrors Admin::InventoryController#update_status exactly: the transition
  # allow-list is evaluated against the LOCKED row, not a stale pre-lock read,
  # so a unit that became `reserved` while we waited is refused by the same
  # rule the real endpoint applies.
  def admin_scrap(inventory_id)
    Inventories::HoldProtection.guard(inventory_id) do |locked|
      allowed = Admin::InventoryController::VALID_STATUS_TRANSITIONS[locked.status] || []
      next false unless allowed.include?('scrap')

      locked.update!(status: :scrap, status_changed_at: Time.current)
    end
  end

  def run_pair(first, second)
    threads = [first, second].map do |work|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { work.call }
      rescue StandardError
        nil
      end
    end
    threads.each { |t| t.join(20) }
  end

  # The outcome that must never happen: the admin destroyed the unit AND a
  # cart still believes it owns it.
  def assert_no_double_outcome!(inventory)
    inventory.reload
    scrapped = inventory.status == 'scrap'
    held = CartInventoryHold.active.where(inventory_id: inventory.id).exists?

    expect(scrapped && held).to be(false),
                                "admin destroyed a unit a cart still holds: " \
                                "status=#{inventory.status} active_hold=#{held}"
  end

  # Race A - a new hold races an admin scrap.
  it 'never lets an admin scrap a unit a cart simultaneously claims' do
    inventory = unit
    cart, item = cart_with_item

    run_pair(
      -> { admin_scrap(inventory.id) },
      -> { claim_hold(cart, item) }
    )

    assert_no_double_outcome!(inventory)
  end

  it 'holds that invariant across repeated rounds' do
    5.times do
      truncate_all!
      fresh_location = create(:inventory_location)
      fresh_product = create(:product, skip_seed_inventory: true, status: :active)
      inventory = create(:inventory, product: fresh_product, status: :damaged)
      inventory.update_columns(
        status: Inventory.statuses['available'],
        item_condition: Inventory.item_conditions['brand_new'],
        inventory_location_id: fresh_location.id
      )
      inventory.reload
      cart = ShoppingCart.create!(user: create(:user), status: 'active', last_activity_at: Time.current)
      item = cart.shopping_cart_items.create!(
        product: fresh_product, product_reference: fresh_product.id,
        condition: :brand_new, quantity: 1, product_name_snapshot: fresh_product.product_name
      )

      run_pair(
        -> { admin_scrap(inventory.id) },
        lambda {
          Carts::HoldInventory.sync(cart: cart, cart_item: item, product: fresh_product,
                                    condition: :brand_new, target_quantity: 1)
        }
      )

      assert_no_double_outcome!(inventory)
    end
  end

  # Race B - an established hold, admin races it while the cart transaction
  # is still open.
  it 'refuses the admin mutation while an established hold is open' do
    inventory = unit
    cart, item = cart_with_item
    hold_gate = Queue.new

    run_pair(
      lambda {
        ActiveRecord::Base.transaction do
          claim_hold(cart, item)
          hold_gate << :held
          sleep 0.5
        end
      },
      lambda {
        hold_gate.pop
        admin_scrap(inventory.id)
      }
    )

    assert_no_double_outcome!(inventory)
    expect(inventory.reload.status).to eq('available')
    expect(CartInventoryHold.active.count).to eq(1)
  end

  # Race C - checkout consuming the hold races an admin scrap.
  it 'produces no invalid double outcome when checkout consumes while admin acts' do
    inventory = unit
    cart, item = cart_with_item
    claim_hold(cart, item)
    held_id = CartInventoryHold.active.for_cart(cart).pluck(:inventory_id).first
    expect(held_id).to eq(inventory.id)

    order = create(:sale_order)
    line = create(:sale_order_item, sale_order: order, product: product, quantity: 1,
                                    preorder_quantity: 0, item_condition: :brand_new,
                                    unit_cost: 40, unit_selling_price: 100,
                                    unit_final_price: 100, total_line_cost: 40)

    run_pair(
      lambda {
        ActiveRecord::Base.transaction do
          InventoryServices::ReserveSaleOrderItem.call(
            line, strict: false, held_inventory_ids: [held_id], holding_cart_id: cart.id
          )
          CartInventoryHold.for_cart(cart).delete_all
        end
      },
      -> { admin_scrap(inventory.id) }
    )

    assert_no_double_outcome!(inventory)
    # Either checkout reserved it, or the admin scrapped it - never both.
    inventory.reload
    reserved = inventory.sale_order_item_id == line.id
    scrapped = inventory.status == 'scrap'
    expect(reserved ^ scrapped).to be(true), "status=#{inventory.status} soi=#{inventory.sale_order_item_id}"
  end
end
