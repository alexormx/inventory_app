# frozen_string_literal: true

require 'rails_helper'

# An admin must not be able to take a physical unit away from the customer
# whose cart is actively holding it. The hold stays the authority for cart
# ownership; this guard just refuses the mutations that would invalidate it.
RSpec.describe Inventories::HoldProtection do
  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true) }

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

  describe '.protected_status?' do
    it 'protects the transitions that steal or destroy a held unit' do
      %w[reserved damaged lost scrap marketing].each do |status|
        expect(described_class.protected_status?(status)).to be(true)
      end
    end

    it 'leaves harmless transitions alone' do
      %w[available sold in_transit returned].each do |status|
        expect(described_class.protected_status?(status)).to be(false)
      end
    end
  end

  describe '.guard' do
    it 'runs the mutation when nothing holds the unit' do
      inventory = unit

      result = described_class.guard(inventory.id) do |locked|
        locked.update!(status: :damaged, status_changed_at: Time.current)
      end

      expect(result).to be_performed
      expect(result.hold).to be_nil
      expect(inventory.reload.status).to eq('damaged')
    end

    it 'refuses the mutation while an active hold owns the unit' do
      inventory = unit
      hold = hold!(inventory)

      result = described_class.guard(inventory.id) do |locked|
        locked.update!(status: :damaged)
      end

      expect(result).to be_blocked
      expect(result.hold.id).to eq(hold.id)
      expect(inventory.reload.status).to eq('available')
    end

    it 'allows the mutation once the hold has expired, with no cleanup run' do
      inventory = unit
      hold!(inventory, expires_at: 1.second.ago)

      result = described_class.guard(inventory.id) do |locked|
        locked.update!(status: :lost)
      end

      expect(result).to be_performed
      expect(inventory.reload.status).to eq('lost')
      # The stale row is still there; it simply does not block.
      expect(CartInventoryHold.count).to eq(1)
    end

    it 'allows the mutation once the hold has been consumed' do
      inventory = unit
      hold = hold!(inventory)
      hold.destroy!

      result = described_class.guard(inventory.id) { |locked| locked.update!(status: :scrap) }

      expect(result).to be_performed
      expect(inventory.reload.status).to eq('scrap')
    end

    # Exact-row awareness: holding one unit must not freeze its siblings.
    it 'protects only the held row, never every unit of the product' do
      held = unit
      free = unit
      hold!(held)

      blocked = described_class.guard(held.id) { |locked| locked.update!(status: :damaged) }
      allowed = described_class.guard(free.id) { |locked| locked.update!(status: :damaged) }

      expect(blocked).to be_blocked
      expect(allowed).to be_performed
      expect(held.reload.status).to eq('available')
      expect(free.reload.status).to eq('damaged')
    end

    it 'reports a missing row without running the block' do
      ran = false
      result = described_class.guard(-1) { ran = true }

      expect(result).to be_blocked
      expect(result.hold).to be_nil
      expect(ran).to be(false)
    end

    it 'yields the locked row, not the caller copy' do
      inventory = unit
      yielded = nil

      described_class.guard(inventory.id) { |locked| yielded = locked }

      expect(yielded).to be_a(Inventory)
      expect(yielded.id).to eq(inventory.id)
    end
  end
end
