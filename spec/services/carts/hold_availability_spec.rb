# frozen_string_literal: true

require 'rails_helper'

# Active cart holds remove a physical unit from everyone else's view of
# availability, while the owning cart keeps seeing what it already holds.
RSpec.describe 'Cart holds and canonical availability' do
  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true, preorder_available: true) }

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

  def hold_for(cart, item, quantity, condition: :brand_new)
    Carts::HoldInventory.sync(
      cart: cart, cart_item: item, product: product,
      condition: condition, target_quantity: quantity
    )
  end

  describe 'Inventories::Availability' do
    it 'hides a held unit from another cart and from an anonymous view' do
      stock(count: 2)
      cart_a = build_cart
      hold_for(cart_a, build_item(cart_a), 1)
      cart_b = build_cart

      expect(Inventories::Availability.for(product, condition: 'brand_new', for_cart: cart_a).available_now).to eq(2)
      expect(Inventories::Availability.for(product, condition: 'brand_new', for_cart: cart_b).available_now).to eq(1)
      expect(Inventories::Availability.for(product, condition: 'brand_new').available_now).to eq(1)
    end

    it 'stops hiding the unit once the hold expires, with no cleanup run' do
      stock(count: 1)
      cart_a = build_cart
      hold_for(cart_a, build_item(cart_a), 1)
      cart_b = build_cart
      expect(Inventories::Availability.for(product, condition: 'brand_new', for_cart: cart_b).available_now).to eq(0)

      CartInventoryHold.update_all(expires_at: 1.second.ago)

      expect(Inventories::Availability.for(product, condition: 'brand_new', for_cart: cart_b).available_now).to eq(1)
      expect(CartInventoryHold.count).to eq(1)
    end

    it 'hides held in-transit units the same way' do
      stock(status: :in_transit, count: 2)
      cart_a = build_cart
      hold_for(cart_a, build_item(cart_a), 1)
      cart_b = build_cart

      expect(Inventories::Availability.for(product, condition: 'brand_new', for_cart: cart_a).in_transit).to eq(2)
      expect(Inventories::Availability.for(product, condition: 'brand_new', for_cart: cart_b).in_transit).to eq(1)
    end

    it 'keeps condition isolation when excluding holds' do
      stock(condition: :brand_new, count: 1)
      stock(condition: :mint, count: 1)
      cart_a = build_cart
      hold_for(cart_a, build_item(cart_a, condition: :mint), 1, condition: :mint)
      cart_b = build_cart

      # Holding a mint unit must not shrink brand_new availability.
      expect(Inventories::Availability.for(product, condition: 'brand_new', for_cart: cart_b).available_now).to eq(1)
      expect(Inventories::Availability.for(product, condition: 'mint', for_cart: cart_b).available_now).to eq(0)
    end

    it 'applies the same rule to the batch counts the catalog uses' do
      stock(count: 2)
      cart_a = build_cart
      hold_for(cart_a, build_item(cart_a), 1)
      cart_b = build_cart

      own = Inventories::Availability.counts_for([product.id], for_cart: cart_a)
      other = Inventories::Availability.counts_for([product.id], for_cart: cart_b)

      expect(own[[product.id, 'brand_new']]).to eq(2)
      expect(other[[product.id, 'brand_new']]).to eq(1)
    end

    it 'applies the rule to batch in-transit counts too' do
      stock(status: :in_transit, count: 2)
      cart_a = build_cart
      hold_for(cart_a, build_item(cart_a), 1)
      cart_b = build_cart

      own = Inventories::Availability.in_transit_counts_for([product.id], for_cart: cart_a)
      other = Inventories::Availability.in_transit_counts_for([product.id], for_cart: cart_b)

      expect(own[[product.id, 'brand_new']]).to eq(2)
      expect(other[[product.id, 'brand_new']]).to eq(1)
    end
  end

  describe 'PreorderAllocator' do
    def preorder_demand(condition: :brand_new, quantity: 1)
      order = create(:sale_order)
      line = create(
        :sale_order_item,
        sale_order: order, product: product,
        quantity: quantity, preorder_quantity: quantity, item_condition: condition,
        unit_cost: 40, unit_selling_price: 100, unit_final_price: 100, total_line_cost: 40 * quantity
      )
      reservation = create(
        :preorder_reservation,
        product: product, user: order.user, sale_order: order,
        sale_order_item: line, quantity: quantity
      )
      [line, reservation]
    end

    it 'cannot allocate a unit that a cart actively holds' do
      rows = stock(count: 1)
      cart = build_cart
      hold_for(cart, build_item(cart), 1)
      _line, reservation = preorder_demand

      expect(Preorders::PreorderAllocator.new(product).call).to eq(0)
      expect(reservation.reload).to be_pending
      expect(rows.first.reload.sale_order_item_id).to be_nil
    end

    it 'can allocate the unit again once the hold expires' do
      stock(count: 1)
      cart = build_cart
      hold_for(cart, build_item(cart), 1)
      line, reservation = preorder_demand
      CartInventoryHold.update_all(expires_at: 1.second.ago)

      expect(Preorders::PreorderAllocator.new(product).call).to eq(1)
      expect(reservation.reload).to be_assigned
      expect(line.reload.inventory_units.count).to eq(1)
    end

    it 'allocates the free unit and leaves the held one alone' do
      rows = stock(count: 2)
      cart = build_cart
      hold_for(cart, build_item(cart), 1)
      held_id = CartInventoryHold.first.inventory_id
      line, _reservation = preorder_demand(quantity: 2)

      expect(Preorders::PreorderAllocator.new(product).call).to eq(1)
      assigned = line.reload.inventory_units.pluck(:id)
      expect(assigned.size).to eq(1)
      expect(assigned).not_to include(held_id)
      expect(assigned.first).to be_in(rows.map(&:id))
      expect(line.preorder_quantity).to eq(1)
    end

    it 'keeps PR #183 condition isolation while excluding holds' do
      stock(condition: :brand_new, count: 1)
      stock(condition: :mint, count: 1)
      cart = build_cart
      # Hold the mint unit; brand_new demand must still be served by brand_new.
      hold_for(cart, build_item(cart, condition: :mint), 1, condition: :mint)
      line, _reservation = preorder_demand(condition: :brand_new)

      expect(Preorders::PreorderAllocator.new(product).call).to eq(1)
      expect(line.reload.inventory_units.map(&:item_condition).uniq).to eq(['brand_new'])
    end
  end
end
