# frozen_string_literal: true

require 'rails_helper'

# Holds follow the durable cart's single write path: adding, changing and
# removing a line keeps the exact physical units it owns in step.
RSpec.describe 'Cart hold lifecycle through ActiveCartMutation' do
  let(:location) { create(:inventory_location) }
  let(:user)     { create(:user) }
  let(:product)  { create(:product, skip_seed_inventory: true) }
  let(:other)    { create(:product, skip_seed_inventory: true) }

  def stock(for_product: product, condition: :brand_new, status: :available, count: 1)
    Array.new(count) do
      inventory = create(:inventory, product: for_product, status: :damaged)
      inventory.update_columns(
        status: Inventory.statuses[status.to_s],
        item_condition: Inventory.item_conditions[condition.to_s],
        inventory_location_id: (status == :available ? location.id : nil)
      )
      inventory.reload
    end
  end

  def cart_for(a_user = user)
    ShoppingCarts::ActiveCartResolver.find(a_user)
  end

  def holds_for(a_user = user)
    cart = cart_for(a_user)
    cart ? CartInventoryHold.active.for_cart(cart) : CartInventoryHold.none
  end

  describe 'adding to the cart' do
    it 'claims one exact unit per item added' do
      rows = stock(count: 3)

      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 2)

      expect(holds_for.count).to eq(2)
      expect(holds_for.pluck(:inventory_id)).to all(be_in(rows.map(&:id)))
    end

    it 'attributes each hold to the cart line that caused it' do
      stock(count: 1)

      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 1)

      line = cart_for.shopping_cart_items.first
      expect(holds_for.first.shopping_cart_item_id).to eq(line.id)
    end

    it 'still adds the line when no physical unit is available to hold' do
      # Preorder/backorder demand has nothing to claim yet; the cart must work.
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 1)

      expect(cart_for.shopping_cart_items.count).to eq(1)
      expect(holds_for.count).to eq(0)
    end

    it 'does not claim a unit another cart already holds' do
      stock(count: 1)
      rival = create(:user)
      ShoppingCarts::ActiveCartMutation.add(user: rival, product: product, condition: 'brand_new', quantity: 1)

      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 1)

      expect(holds_for(rival).count).to eq(1)
      expect(holds_for(user).count).to eq(0)
      expect(CartInventoryHold.count).to eq(1)
    end
  end

  describe 'increasing quantity' do
    it 'keeps the units it already holds and claims only the delta' do
      stock(count: 4)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 1)
      original = holds_for.pluck(:inventory_id)

      ShoppingCarts::ActiveCartMutation.set_quantity(user: user, product: product, condition: 'brand_new', quantity: 3)

      expect(holds_for.count).to eq(3)
      expect(holds_for.pluck(:inventory_id)).to include(*original)
    end
  end

  describe 'decreasing quantity' do
    it 'releases only the excess' do
      stock(count: 3)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 3)
      expect(holds_for.count).to eq(3)

      ShoppingCarts::ActiveCartMutation.set_quantity(user: user, product: product, condition: 'brand_new', quantity: 1)

      expect(holds_for.count).to eq(1)
      expect(CartInventoryHold.count).to eq(1)
    end

    it 'leaves another line of the same cart untouched' do
      stock(count: 2)
      stock(for_product: other, count: 2)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 2)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: other, condition: 'brand_new', quantity: 2)

      ShoppingCarts::ActiveCartMutation.set_quantity(user: user, product: product, condition: 'brand_new', quantity: 1)

      expect(CartInventoryHold.active.joins(:inventory).where(inventories: { product_id: product.id }).count).to eq(1)
      expect(CartInventoryHold.active.joins(:inventory).where(inventories: { product_id: other.id }).count).to eq(2)
    end
  end

  describe 'removing a line' do
    it 'releases that lineholds and deletes the rows outright' do
      stock(count: 2)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 2)

      ShoppingCarts::ActiveCartMutation.remove(user: user, product: product, condition: 'brand_new')

      expect(CartInventoryHold.count).to eq(0)
    end

    it 'never leaves an orphaned hold with a live expiry behind' do
      stock(count: 1)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 1)

      ShoppingCarts::ActiveCartMutation.remove(user: user, product: product, condition: 'brand_new')

      orphans = CartInventoryHold.where(shopping_cart_item_id: nil)
      expect(orphans).to be_empty
    end

    it 'keeps other lines holds when one line is removed' do
      stock(count: 1)
      stock(for_product: other, count: 1)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 1)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: other, condition: 'brand_new', quantity: 1)

      ShoppingCarts::ActiveCartMutation.remove(user: user, product: product, condition: 'brand_new')

      expect(CartInventoryHold.active.count).to eq(1)
      expect(CartInventoryHold.active.first.inventory.product_id).to eq(other.id)
    end

    it 'releases a released unit back to another cart' do
      stock(count: 1)
      rival = create(:user)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 1)
      ShoppingCarts::ActiveCartMutation.remove(user: user, product: product, condition: 'brand_new')

      ShoppingCarts::ActiveCartMutation.add(user: rival, product: product, condition: 'brand_new', quantity: 1)

      expect(holds_for(rival).count).to eq(1)
    end
  end

  describe 'clearing the cart' do
    it 'releases every hold the cart owned' do
      stock(count: 2)
      stock(for_product: other, count: 1)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new', quantity: 2)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: other, condition: 'brand_new', quantity: 1)

      ShoppingCarts::ActiveCartMutation.clear(user: user)

      expect(CartInventoryHold.count).to eq(0)
    end
  end
end
