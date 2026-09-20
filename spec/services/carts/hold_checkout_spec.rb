# frozen_string_literal: true

require 'rails_helper'

# Checkout must reserve the exact physical units the cart already holds,
# never equivalent ones, and must not honour a hold that has expired.
RSpec.describe 'Checkout consumption of cart inventory holds' do
  let(:user)            { create(:user) }
  let!(:address)        { create(:shipping_address, user: user) }
  let!(:shipping_method) { create(:shipping_method, :standard) }
  let(:location)        { create(:inventory_location) }
  let(:product) do
    create(:product, skip_seed_inventory: true, selling_price: 100,
                     preorder_available: false, backorder_allowed: false, status: :active)
  end

  class HoldTestCart
    attr_reader :items

    def initialize(items_array) = @items = items_array
    def empty? = @items.empty?
    def blank? = @items.empty?
    def total = @items.sum { |item| item[:price] * item[:quantity] }
  end

  def stock(count:, condition: :brand_new, status: :available)
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

  def cart_with_holds(quantity:, condition: 'brand_new')
    ShoppingCarts::ActiveCartMutation.add(
      user: user, product: product, condition: condition, quantity: quantity
    )
    ShoppingCarts::ActiveCartResolver.find(user)
  end

  def session_cart(quantity, condition: 'brand_new')
    HoldTestCart.new([{
      product: product, condition: condition, quantity: quantity,
      price: product.selling_price, collectible: condition != 'brand_new',
      label: 'Nuevo', line_total: product.selling_price * quantity
    }])
  end

  def checkout(shopping_cart:, quantity:, condition: 'brand_new')
    described = Checkout::CreateOrder.new(
      user: user,
      cart: session_cart(quantity, condition: condition),
      shipping_address_id: address.id,
      shipping_method: 'standard',
      payment_method: 'transferencia_bancaria',
      notes: '',
      shopping_cart: shopping_cart
    )
    described.call
  end

  it 'reserves the exact units the cart held, not equivalent ones' do
    rows = stock(count: 5)
    cart = cart_with_holds(quantity: 2)
    held_ids = CartInventoryHold.active.for_cart(cart).pluck(:inventory_id).sort
    expect(held_ids.size).to eq(2)

    result = checkout(shopping_cart: cart, quantity: 2)

    expect(result).to be_success
    line = result.sale_order.sale_order_items.first
    expect(line.inventory_units.pluck(:id).sort).to eq(held_ids)
    # The other three units were never touched.
    untouched = rows.map(&:id) - held_ids
    expect(Inventory.where(id: untouched).pluck(:sale_order_id).uniq).to eq([nil])
  end

  it 'consumes the holds once the transfer succeeds' do
    stock(count: 2)
    cart = cart_with_holds(quantity: 2)

    result = checkout(shopping_cart: cart, quantity: 2)

    expect(result).to be_success
    expect(CartInventoryHold.where(shopping_cart_id: cart.id)).to be_empty
  end

  it 'falls back to free stock only for quantity beyond what it holds' do
    # Only one unit exists when the line is created, so the cart holds 1. Two
    # more units arrive afterwards, leaving the line at quantity 3 with a
    # single held unit: checkout must keep that one and top up with the rest.
    stock(count: 1)
    cart = cart_with_holds(quantity: 3)
    held_ids = CartInventoryHold.active.for_cart(cart).pluck(:inventory_id)
    expect(held_ids.size).to eq(1)
    stock(count: 2)

    result = checkout(shopping_cart: cart, quantity: 3)

    expect(result).to be_success
    assigned = result.sale_order.sale_order_items.first.inventory_units.pluck(:id)
    expect(assigned.size).to eq(3)
    expect(assigned).to include(*held_ids)
  end

  it 'does not honour an expired hold as owned inventory' do
    stock(count: 1)
    rival = create(:user)
    cart = cart_with_holds(quantity: 1)
    held_id = CartInventoryHold.active.for_cart(cart).pluck(:inventory_id).first

    # The hold lapses and a rival cart legitimately takes the unit.
    CartInventoryHold.update_all(expires_at: 1.second.ago)
    ShoppingCarts::ActiveCartMutation.add(user: rival, product: product, condition: 'brand_new', quantity: 1)
    rival_cart = ShoppingCarts::ActiveCartResolver.find(rival)
    expect(CartInventoryHold.active.for_cart(rival_cart).pluck(:inventory_id)).to eq([held_id])

    result = checkout(shopping_cart: cart, quantity: 1)

    # The unit now belongs to the rival's cart, so this checkout cannot take it.
    expect(result).not_to be_success
    expect(Inventory.find(held_id).sale_order_id).to be_nil
    expect(CartInventoryHold.active.for_cart(rival_cart).count).to eq(1)
  end

  it 'still works for a checkout with no holds at all' do
    stock(count: 2)
    cart = ShoppingCarts::ActiveCartMutation.add(
      user: user, product: product, condition: 'brand_new', quantity: 2
    ).cart
    CartInventoryHold.delete_all

    result = checkout(shopping_cart: cart, quantity: 2)

    expect(result).to be_success
    expect(result.sale_order.sale_order_items.first.inventory_units.count).to eq(2)
  end

  it 'leaves holds and inventory intact when checkout fails' do
    stock(count: 1)
    cart = cart_with_holds(quantity: 1)
    held_id = CartInventoryHold.active.for_cart(cart).pluck(:inventory_id).first

    # Ask for more than exists on a product that forbids preorder/backorder.
    result = checkout(shopping_cart: cart, quantity: 4)

    expect(result).not_to be_success
    expect(Inventory.find(held_id).sale_order_id).to be_nil
    expect(CartInventoryHold.active.for_cart(cart).pluck(:inventory_id)).to eq([held_id])
  end

  it 'cannot reserve a unit another cart holds, even with stock present' do
    stock(count: 1)
    rival = create(:user)
    ShoppingCarts::ActiveCartMutation.add(user: rival, product: product, condition: 'brand_new', quantity: 1)
    # Our cart got nothing, because the only unit was already held.
    cart = cart_with_holds(quantity: 1)
    expect(CartInventoryHold.active.for_cart(cart).count).to eq(0)

    result = checkout(shopping_cart: cart, quantity: 1)

    expect(result).not_to be_success
  end
end
