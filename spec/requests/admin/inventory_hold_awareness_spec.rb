# frozen_string_literal: true

require 'rails_helper'

# Server-side enforcement, not a disabled button: the admin endpoints
# themselves must refuse to take a unit that a customer's cart is holding.
RSpec.describe 'Admin inventory cart-hold awareness', type: :request do
  let(:admin)    { create(:user, :admin) }
  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true) }

  before { sign_in admin }

  def unit(status: :available, located: true)
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(
      status: Inventory.statuses[status.to_s],
      item_condition: Inventory.item_conditions['brand_new'],
      inventory_location_id: (located ? location.id : nil)
    )
    inventory.reload
  end

  def hold!(inventory, expires_at: CartInventoryHold::HOLD_DURATION.from_now)
    cart = ShoppingCart.create!(user: create(:user), status: 'active', last_activity_at: Time.current)
    item = cart.shopping_cart_items.create!(
      product: product, product_reference: product.id,
      condition: :brand_new, quantity: 1, product_name_snapshot: product.product_name
    )
    CartInventoryHold.create!(
      shopping_cart: cart, shopping_cart_item: item,
      inventory: inventory, expires_at: expires_at
    )
  end

  describe 'PATCH update_status' do
    it 'refuses to scrap a unit a cart is actively holding' do
      inventory = unit
      hold!(inventory)

      patch update_status_admin_inventory_path(inventory), params: { status: 'scrap' }

      expect(inventory.reload.status).to eq('available')
      # The reason must name the hold, not a misleading "transition not
      # allowed" - the transition IS allowed; a customer simply owns the unit.
      expect(flash[:alert]).to match(/retenida en el carrito/i)
      expect(flash[:alert]).to be_present
    end

    it 'refuses to manually reserve a held unit for another order' do
      inventory = unit
      hold!(inventory)

      patch update_status_admin_inventory_path(inventory), params: { status: 'reserved' }

      expect(inventory.reload.status).to eq('available')
      expect(inventory.sale_order_id).to be_nil
    end

    %w[damaged lost marketing].each do |status|
      it "refuses to mark a held unit #{status}" do
        inventory = unit
        hold!(inventory)

        patch update_status_admin_inventory_path(inventory), params: { status: status }

        expect(inventory.reload.status).to eq('available')
      end
    end

    it 'allows the mutation once the hold has expired, without waiting for cleanup' do
      inventory = unit
      hold!(inventory, expires_at: 1.second.ago)

      patch update_status_admin_inventory_path(inventory), params: { status: 'damaged' }

      expect(inventory.reload.status).to eq('damaged')
      expect(CartInventoryHold.count).to eq(1)
    end

    it 'allows the mutation when the hold was consumed by checkout' do
      inventory = unit
      hold!(inventory).destroy!

      patch update_status_admin_inventory_path(inventory), params: { status: 'lost' }

      expect(inventory.reload.status).to eq('lost')
    end

    it 'leaves unheld inventory behaving exactly as before' do
      inventory = unit

      patch update_status_admin_inventory_path(inventory), params: { status: 'damaged' }

      expect(inventory.reload.status).to eq('damaged')
    end

    it 'protects only the held row, not every unit of the product' do
      held = unit
      free = unit
      hold!(held)

      patch update_status_admin_inventory_path(held), params: { status: 'scrap' }
      patch update_status_admin_inventory_path(free), params: { status: 'scrap' }

      expect(held.reload.status).to eq('available')
      expect(free.reload.status).to eq('scrap')
    end

    it 'still rejects a transition the allow-list forbids, held or not' do
      inventory = unit(status: :sold, located: false)

      patch update_status_admin_inventory_path(inventory), params: { status: 'available' }

      expect(inventory.reload.status).to eq('sold')
    end
  end

  describe 'PATCH update_location' do
    it 'refuses to unlocate a held unit, which would hide it from its owner' do
      inventory = unit
      hold!(inventory)

      patch update_location_admin_inventory_path(inventory), params: { inventory_location_id: '' }

      expect(inventory.reload.inventory_location_id).to eq(location.id)
    end

    it 'still allows moving a held unit between real locations' do
      inventory = unit
      hold!(inventory)
      other = create(:inventory_location)

      patch update_location_admin_inventory_path(inventory), params: { inventory_location_id: other.id }

      expect(inventory.reload.inventory_location_id).to eq(other.id)
    end

    it 'allows unlocating once the hold expired' do
      inventory = unit
      hold!(inventory, expires_at: 1.second.ago)

      patch update_location_admin_inventory_path(inventory), params: { inventory_location_id: '' }

      expect(inventory.reload.inventory_location_id).to be_nil
    end
  end

  describe 'query count' do
    # Scoped to cart_inventory_holds on purpose: the admin list has its own
    # pre-existing query profile, and what this PR must not do is add one
    # hold lookup per physical row.
    def hold_query_count(&block)
      count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:name] == 'SCHEMA'

        count += 1 if payload[:sql].to_s.include?('cart_inventory_holds')
      end
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
      count
    end

    it 'does not issue one hold query per inventory row as the list grows' do
      3.times { hold!(unit) }
      get items_admin_inventory_path(product.id) # warm
      small = hold_query_count { get items_admin_inventory_path(product.id) }

      5.times { hold!(unit) }

      large = hold_query_count { get items_admin_inventory_path(product.id) }

      expect(large).to eq(small)
    end
  end

  describe 'admin inventory display' do
    it 'shows a hold indicator for an actively held unit' do
      inventory = unit
      hold!(inventory)

      get items_admin_inventory_path(inventory.product_id)

      expect(response.body).to include('Retenido en carrito')
    end

    it 'shows no hold indicator for an unheld unit' do
      unit

      get items_admin_inventory_path(product.id)

      expect(response.body).not_to include('Retenido en carrito')
    end

    it 'shows no hold indicator once the hold expired' do
      inventory = unit
      hold!(inventory, expires_at: 1.second.ago)

      get items_admin_inventory_path(inventory.product_id)

      expect(response.body).not_to include('Retenido en carrito')
    end
  end
end
