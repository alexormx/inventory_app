# frozen_string_literal: true

require 'rails_helper'

# The storefront must keep showing a customer the units their own cart holds,
# while hiding units held by someone else.
RSpec.describe 'Storefront visibility of cart inventory holds', type: :request do
  let(:location) { create(:inventory_location) }
  let(:product) do
    create(:product, skip_seed_inventory: true, status: :active,
                     preorder_available: false, backorder_allowed: false)
  end

  def unit
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(
      status: Inventory.statuses['available'],
      item_condition: Inventory.item_conditions['brand_new'],
      inventory_location_id: location.id
    )
    inventory
  end

  def hold_for(user)
    ShoppingCarts::ActiveCartMutation.add(
      user: user, product: product, condition: 'brand_new', quantity: 1
    )
    ShoppingCarts::ActiveCartResolver.find(user)
  end

  it 'lets the owning customer keep adding the unit their cart already holds' do
    unit
    owner = create(:user)
    cart = hold_for(owner)
    expect(CartInventoryHold.active.for_cart(cart).count).to eq(1)

    sign_in owner
    # The only unit is held by this very cart, so its own view still sees it.
    expect(
      Inventories::Availability.for(product, condition: 'brand_new', for_cart: cart).available_now
    ).to eq(1)

    get catalog_path
    expect(response).to have_http_status(:ok)
  end

  it 'refuses a rival customer the unit that is already held' do
    unit
    owner = create(:user)
    hold_for(owner)
    rival = create(:user)

    sign_in rival
    post cart_items_path, params: { product_id: product.id, condition: 'brand_new' }

    rival_cart = ShoppingCarts::ActiveCartResolver.find(rival)
    # The rival may have a cart line, but it owns no physical unit.
    expect(CartInventoryHold.active.for_cart(rival_cart).count).to eq(0) if rival_cart
    expect(CartInventoryHold.active.count).to eq(1)
  end

  it 'shows the unit again to everyone once the hold lapses' do
    unit
    owner = create(:user)
    hold_for(owner)
    rival = create(:user)
    rival_cart = ShoppingCart.create!(user: rival, status: 'active', last_activity_at: Time.current)

    expect(
      Inventories::Availability.for(product, condition: 'brand_new', for_cart: rival_cart).available_now
    ).to eq(0)

    CartInventoryHold.update_all(expires_at: 1.second.ago)

    expect(
      Inventories::Availability.for(product, condition: 'brand_new', for_cart: rival_cart).available_now
    ).to eq(1)
  end
end
