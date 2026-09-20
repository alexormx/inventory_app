# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Carts::HoldInventory do
  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true) }

  def build_cart(user = create(:user))
    ShoppingCart.create!(user: user, status: 'active', last_activity_at: Time.current)
  end

  def build_item(cart, condition: :brand_new, quantity: 1)
    cart.shopping_cart_items.create!(
      product: product, product_reference: product.id,
      condition: condition, quantity: quantity, product_name_snapshot: product.product_name
    )
  end

  def stock(condition: :brand_new, status: :available, count: 1)
    Array.new(count) do
      inventory = create(:inventory, product: product, status: :damaged)
      inventory.update_columns(
        status: Inventory.statuses[status.to_s],
        item_condition: Inventory.item_conditions[condition.to_s],
        inventory_location_id: (status == :available ? location.id : nil)
      )
      inventory.reload
    end
  end

  def sync(cart, item, quantity, condition: :brand_new)
    described_class.sync(
      cart: cart, cart_item: item, product: product,
      condition: condition, target_quantity: quantity
    )
  end

  describe 'claiming free inventory' do
    it 'claims exactly the requested number of specific rows' do
      rows = stock(count: 3)
      cart = build_cart
      item = build_item(cart, quantity: 2)

      result = sync(cart, item, 2)

      expect(result.held).to eq(2)
      held = CartInventoryHold.active.for_cart_item(item)
      expect(held.count).to eq(2)
      expect(held.pluck(:inventory_id)).to all(be_in(rows.map(&:id)))
      expect(held.pluck(:shopping_cart_id).uniq).to eq([cart.id])
    end

    it 'sets expires_at four hours out' do
      stock(count: 1)
      cart = build_cart
      item = build_item(cart)

      sync(cart, item, 1)

      hold = CartInventoryHold.for_cart_item(item).first
      expect(hold.expires_at).to be_within(1.minute).of(CartInventoryHold::HOLD_DURATION.from_now)
    end

    it 'only claims rows of the requested condition' do
      brand_new = stock(condition: :brand_new, count: 1)
      stock(condition: :mint, count: 5)
      cart = build_cart
      item = build_item(cart, condition: :brand_new, quantity: 3)

      result = sync(cart, item, 3)

      # Only one brand_new row exists; mint stock is not eligible.
      expect(result.held).to eq(1)
      expect(CartInventoryHold.active.pluck(:inventory_id)).to eq([brand_new.first.id])
    end

    it 'reports a partial claim without overcommitting when stock is short' do
      stock(count: 1)
      cart = build_cart
      item = build_item(cart, quantity: 5)

      result = sync(cart, item, 5)

      expect(result.held).to eq(1)
      expect(result.requested).to eq(5)
      expect(result).not_to be_complete
      expect(CartInventoryHold.count).to eq(1)
    end

    it 'never claims unlocated or unsellable rows' do
      stock(status: :available, count: 1).first.update_columns(inventory_location_id: nil)
      cart = build_cart
      item = build_item(cart)

      expect(sync(cart, item, 1).held).to eq(0)
    end

    it 'claims in-transit rows, matching the sellable rule' do
      rows = stock(status: :in_transit, count: 1)
      cart = build_cart
      item = build_item(cart)

      expect(sync(cart, item, 1).held).to eq(1)
      expect(CartInventoryHold.first.inventory_id).to eq(rows.first.id)
    end
  end

  describe 'competition between carts' do
    it 'does not let a second cart steal an actively held row' do
      rows = stock(count: 1)
      cart_a = build_cart
      item_a = build_item(cart_a)
      sync(cart_a, item_a, 1)

      cart_b = build_cart
      item_b = build_item(cart_b)
      result = sync(cart_b, item_b, 1)

      expect(result.held).to eq(0)
      expect(CartInventoryHold.count).to eq(1)
      expect(CartInventoryHold.first.shopping_cart_id).to eq(cart_a.id)
      expect(CartInventoryHold.first.inventory_id).to eq(rows.first.id)
    end

    it 'lets a second cart atomically reclaim an expired hold, reusing the row' do
      rows = stock(count: 1)
      cart_a = build_cart
      item_a = build_item(cart_a)
      sync(cart_a, item_a, 1)
      original = CartInventoryHold.first
      original.update_columns(expires_at: 1.second.ago)

      cart_b = build_cart
      item_b = build_item(cart_b)
      result = sync(cart_b, item_b, 1)

      expect(result.held).to eq(1)
      # Reclaimed in place: still exactly one row for this physical unit.
      expect(CartInventoryHold.count).to eq(1)
      reclaimed = CartInventoryHold.first
      expect(reclaimed.id).to eq(original.id)
      expect(reclaimed.inventory_id).to eq(rows.first.id)
      expect(reclaimed.shopping_cart_id).to eq(cart_b.id)
      expect(reclaimed.shopping_cart_item_id).to eq(item_b.id)
      expect(reclaimed).to be_active
      expect(reclaimed.updated_at).to be > original.updated_at
    end

    it 'gives each cart a different row when several are free' do
      stock(count: 2)
      cart_a = build_cart
      cart_b = build_cart
      item_a = build_item(cart_a)
      item_b = build_item(cart_b)

      sync(cart_a, item_a, 1)
      sync(cart_b, item_b, 1)

      ids = CartInventoryHold.active.pluck(:inventory_id)
      expect(ids.uniq.size).to eq(2)
      expect(CartInventoryHold.count).to eq(2)
    end
  end

  describe 'quantity increase' do
    it 'keeps existing valid holds and allocates only the delta' do
      stock(count: 4)
      cart = build_cart
      item = build_item(cart, quantity: 1)
      sync(cart, item, 1)
      original_ids = CartInventoryHold.for_cart_item(item).pluck(:inventory_id)
      original_updated = CartInventoryHold.for_cart_item(item).pluck(:updated_at)

      result = sync(cart, item, 3)

      expect(result.held).to eq(3)
      current = CartInventoryHold.active.for_cart_item(item)
      expect(current.count).to eq(3)
      expect(current.pluck(:inventory_id)).to include(*original_ids)
      # The preserved hold was not rewritten.
      expect(CartInventoryHold.where(inventory_id: original_ids).pluck(:updated_at))
        .to eq(original_updated)
    end
  end

  describe 'quantity decrease' do
    it 'releases only the excess and preserves the rest' do
      stock(count: 4)
      cart = build_cart
      item = build_item(cart, quantity: 4)
      sync(cart, item, 4)
      expect(CartInventoryHold.active.for_cart_item(item).count).to eq(4)

      result = sync(cart, item, 2)

      expect(result.held).to eq(2)
      expect(CartInventoryHold.active.for_cart_item(item).count).to eq(2)
      expect(CartInventoryHold.count).to eq(2)
    end

    it 'does not touch another line of the same cart' do
      stock(condition: :brand_new, count: 2)
      stock(condition: :mint, count: 2)
      cart = build_cart
      new_item = build_item(cart, condition: :brand_new, quantity: 2)
      mint_item = build_item(cart, condition: :mint, quantity: 2)
      sync(cart, new_item, 2, condition: :brand_new)
      sync(cart, mint_item, 2, condition: :mint)

      sync(cart, new_item, 1, condition: :brand_new)

      expect(CartInventoryHold.active.for_cart_item(new_item).count).to eq(1)
      expect(CartInventoryHold.active.for_cart_item(mint_item).count).to eq(2)
    end
  end

  describe 'release_all' do
    it 'releases every hold of one line and leaves other lines alone' do
      stock(condition: :brand_new, count: 2)
      stock(condition: :mint, count: 1)
      cart = build_cart
      new_item = build_item(cart, condition: :brand_new, quantity: 2)
      mint_item = build_item(cart, condition: :mint, quantity: 1)
      sync(cart, new_item, 2, condition: :brand_new)
      sync(cart, mint_item, 1, condition: :mint)

      described_class.release_all(cart_item: new_item)

      expect(CartInventoryHold.for_cart_item(new_item).count).to eq(0)
      expect(CartInventoryHold.active.for_cart_item(mint_item).count).to eq(1)
    end

    it 'deletes the rows rather than leaving them orphaned with a live expiry' do
      stock(count: 1)
      cart = build_cart
      item = build_item(cart)
      sync(cart, item, 1)

      described_class.release_all(cart_item: item)

      expect(CartInventoryHold.count).to eq(0)
    end
  end
end
