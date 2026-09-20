# frozen_string_literal: true

require 'rails_helper'

# Hold exclusion is enforced at two independent layers: the allocator's supply
# budget, and ReserveSaleOrderItem's locked candidate selection. Either alone
# keeps the invariant, which is why removing just one is not observable from
# the outside. These examples pin each layer on its own so a future refactor
# cannot quietly delete both.
RSpec.describe 'Cart hold exclusion, layer by layer' do
  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true, preorder_available: true) }

  def unit(condition: :brand_new, status: :available)
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(
      status: Inventory.statuses[status.to_s],
      item_condition: Inventory.item_conditions[condition.to_s],
      inventory_location_id: (status == :available ? location.id : nil)
    )
    inventory.reload
  end

  def held_unit
    cart = ShoppingCart.create!(user: create(:user), status: 'active', last_activity_at: Time.current)
    item = cart.shopping_cart_items.create!(
      product: product, product_reference: product.id,
      condition: :brand_new, quantity: 1, product_name_snapshot: product.product_name
    )
    Carts::HoldInventory.sync(
      cart: cart, cart_item: item, product: product,
      condition: :brand_new, target_quantity: 1
    )
    [cart, CartInventoryHold.active.for_cart(cart).first.inventory_id]
  end

  def sale_line(quantity: 1, condition: :brand_new)
    order = create(:sale_order)
    create(:sale_order_item, sale_order: order, product: product, quantity: quantity,
                             preorder_quantity: 0, item_condition: condition,
                             unit_cost: 40, unit_selling_price: 100,
                             unit_final_price: 100, total_line_cost: 40 * quantity)
  end

  describe 'layer 1: the allocator supply budget' do
    it 'does not count a held unit as preorder supply' do
      unit
      _cart, held_id = held_unit

      supply = Inventories::Availability
               .claimable(Inventory.customer_sellable)
               .where(product_id: product.id)
               .group(:item_condition)
               .count

      expect(supply.values.sum).to eq(0)
      expect(Inventory.customer_sellable.where(product_id: product.id).pluck(:id)).to include(held_id)
    end

    it 'counts it again once the hold expires' do
      unit
      held_unit
      CartInventoryHold.update_all(expires_at: 1.second.ago)

      supply = Inventories::Availability
               .claimable(Inventory.customer_sellable)
               .where(product_id: product.id)
               .count

      expect(supply).to eq(1)
    end
  end

  describe 'layer 2: locked candidate selection' do
    it 'never reserves a unit another cart holds, even asked directly' do
      unit
      _cart, held_id = held_unit
      line = sale_line

      result = InventoryServices::ReserveSaleOrderItem.call(line, strict: false)

      expect(result.assigned).to eq(0)
      expect(Inventory.find(held_id).sale_order_item_id).to be_nil
    end

    it 'reserves it once the hold expires' do
      unit
      _cart, held_id = held_unit
      CartInventoryHold.update_all(expires_at: 1.second.ago)

      # Creating the line runs the reservation callback, which is the real
      # production path; the unit is free again, so it lands on the line.
      line = sale_line

      expect(Inventory.find(held_id).sale_order_item_id).to eq(line.id)
    end

    it 'refuses a stale id whose hold lapsed and was reclaimed by another cart' do
      unit
      stale_cart, held_id = held_unit
      # The line is created while the unit is held, so the callback gets nothing.
      line = sale_line
      expect(Inventory.find(held_id).sale_order_item_id).to be_nil

      # The hold lapses and a rival legitimately takes the unit.
      CartInventoryHold.update_all(expires_at: 1.second.ago)
      rival = ShoppingCart.create!(user: create(:user), status: 'active', last_activity_at: Time.current)
      rival_item = rival.shopping_cart_items.create!(
        product: product, product_reference: product.id,
        condition: :brand_new, quantity: 1, product_name_snapshot: product.product_name
      )
      Carts::HoldInventory.sync(cart: rival, cart_item: rival_item, product: product,
                                condition: :brand_new, target_quantity: 1)

      # The stale id is offered exactly as a slow checkout would offer it.
      result = InventoryServices::ReserveSaleOrderItem.call(
        line, strict: false,
        held_inventory_ids: [held_id], holding_cart_id: stale_cart.id
      )

      expect(result.assigned).to eq(0)
      expect(Inventory.find(held_id).sale_order_item_id).to be_nil
    end

    it 'consumes a caller-supplied id while its hold is still active and owned' do
      unit
      cart, held_id = held_unit
      line = sale_line
      expect(Inventory.find(held_id).sale_order_item_id).to be_nil

      result = InventoryServices::ReserveSaleOrderItem.call(
        line, strict: false,
        held_inventory_ids: [held_id], holding_cart_id: cart.id
      )

      expect(result.assigned).to eq(1)
      expect(Inventory.find(held_id).sale_order_item_id).to eq(line.id)
    end

    it 'ignores held ids when no owning cart is supplied to prove them' do
      unit
      _cart, held_id = held_unit
      line = sale_line

      result = InventoryServices::ReserveSaleOrderItem.call(
        line, strict: false, held_inventory_ids: [held_id]
      )

      expect(result.assigned).to eq(0)
      expect(Inventory.find(held_id).sale_order_item_id).to be_nil
    end
  end
end
