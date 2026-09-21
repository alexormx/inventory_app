# frozen_string_literal: true

require 'rails_helper'

# The held ids ride from Checkout::CreateOrder to the reservation callback on
# a transient attr_accessor. They are HINTS identifying what must be re-proven;
# the database stays authoritative. These examples pin both halves of that
# contract: the hints reach the right line and only that line, and a hint that
# cannot be proven buys nothing.
RSpec.describe 'Transient held_inventory_ids transport' do
  let(:user)             { create(:user) }
  let!(:address)         { create(:shipping_address, user: user) }
  let!(:shipping_method) { create(:shipping_method, :standard) }
  let(:location)         { create(:inventory_location) }

  let(:product_a) do
    create(:product, skip_seed_inventory: true, selling_price: 100,
                     preorder_available: false, backorder_allowed: false, status: :active)
  end
  let(:product_b) do
    create(:product, skip_seed_inventory: true, selling_price: 100,
                     preorder_available: false, backorder_allowed: false, status: :active)
  end

  class TransientTestCart
    attr_reader :items

    def initialize(items_array) = @items = items_array
    def empty? = @items.empty?
    def blank? = @items.empty?
    def total = @items.sum { |item| item[:price] * item[:quantity] }
  end

  def stock(for_product, count: 1)
    Array.new(count) do
      inventory = create(:inventory, product: for_product, status: :damaged)
      inventory.update_columns(
        status: Inventory.statuses['available'],
        item_condition: Inventory.item_conditions['brand_new'],
        inventory_location_id: location.id
      )
      inventory.reload
    end
  end

  def line_for(a_product, quantity)
    {
      product: a_product, condition: 'brand_new', quantity: quantity,
      price: a_product.selling_price, collectible: false,
      label: 'Nuevo', line_total: a_product.selling_price * quantity
    }
  end

  def checkout(cart, items)
    Checkout::CreateOrder.new(
      user: user, cart: TransientTestCart.new(items),
      shipping_address_id: address.id, shipping_method: 'standard',
      payment_method: 'transferencia_bancaria', notes: '', shopping_cart: cart
    ).call
  end

  it 'gives each line only its own held units, never another line\'s' do
    stock(product_a, count: 1)
    stock(product_b, count: 1)
    ShoppingCarts::ActiveCartMutation.add(user: user, product: product_a, condition: 'brand_new', quantity: 1)
    ShoppingCarts::ActiveCartMutation.add(user: user, product: product_b, condition: 'brand_new', quantity: 1)
    cart = ShoppingCarts::ActiveCartResolver.find(user)

    held = CartInventoryHold.active.for_cart(cart).joins(:inventory)
                            .pluck('inventories.product_id', :inventory_id).to_h
    expect(held.keys).to contain_exactly(product_a.id, product_b.id)

    result = checkout(cart, [line_for(product_a, 1), line_for(product_b, 1)])

    expect(result).to be_success
    result.sale_order.sale_order_items.each do |line|
      expect(line.inventory_units.pluck(:id)).to eq([held[line.product_id]])
      expect(line.inventory_units.pluck(:product_id).uniq).to eq([line.product_id])
    end
  end

  it 'leaves holds and inventory untouched when the transaction rolls back' do
    units = stock(product_a, count: 1)
    ShoppingCarts::ActiveCartMutation.add(user: user, product: product_a, condition: 'brand_new', quantity: 1)
    cart = ShoppingCarts::ActiveCartResolver.find(user)
    held_id = CartInventoryHold.active.for_cart(cart).pluck(:inventory_id).first
    expect(held_id).to eq(units.first.id)

    # Blow up after the line is created and its unit reserved, but before the
    # transaction commits.
    allow(OrderShippingAddress).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'boom')

    expect { checkout(cart, [line_for(product_a, 1)]) }.to raise_error(ActiveRecord::StatementInvalid)

    # Inventory ownership rolled back, and the hold survived intact.
    inventory = Inventory.find(held_id)
    expect(inventory.sale_order_id).to be_nil
    expect(inventory.sale_order_item_id).to be_nil
    expect(inventory.status).to eq('available')
    expect(SaleOrderItem.where(product_id: product_a.id)).to be_empty
    hold = CartInventoryHold.active.for_cart(cart).first
    expect(hold).to be_present
    expect(hold.inventory_id).to eq(held_id)
  end

  it 'ignores a hint that no longer names an active hold of this cart' do
    units = stock(product_a, count: 1)
    ShoppingCarts::ActiveCartMutation.add(user: user, product: product_a, condition: 'brand_new', quantity: 1)
    cart = ShoppingCarts::ActiveCartResolver.find(user)

    # The hold lapses; the hint is now worthless and the unit is ordinary free
    # stock that anyone, including this checkout, may take on the normal path.
    CartInventoryHold.update_all(expires_at: 1.second.ago)

    result = checkout(cart, [line_for(product_a, 1)])

    expect(result).to be_success
    line = result.sale_order.sale_order_items.first
    expect(line.inventory_units.pluck(:id)).to eq([units.first.id])
    # The lapsed hold row was cleared with the rest of the cart's holds.
    expect(CartInventoryHold.where(shopping_cart_id: cart.id)).to be_empty
  end
end
