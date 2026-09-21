# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Carts::ExpireInventoryHoldsJob do
  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true) }

  def hold(expires_at:)
    cart = ShoppingCart.create!(user: create(:user), status: 'active', last_activity_at: Time.current)
    inventory = create(:inventory, product: product, status: :available, inventory_location: location)
    CartInventoryHold.create!(shopping_cart: cart, inventory: inventory, expires_at: expires_at)
  end

  it 'deletes expired holds and keeps active ones' do
    stale = hold(expires_at: 1.minute.ago)
    live  = hold(expires_at: 1.hour.from_now)

    expect(described_class.new.perform).to eq(1)

    expect(CartInventoryHold.where(id: stale.id)).to be_empty
    expect(CartInventoryHold.where(id: live.id)).to exist
  end

  it 'is pure hygiene: availability already ignores an expired hold before it runs' do
    stale = hold(expires_at: 1.minute.ago)
    inventory = stale.inventory

    # The row is still there, and the unit is already claimable again.
    expect(CartInventoryHold.where(id: stale.id)).to exist
    expect(Inventories::Availability.claimable(Inventory.where(id: inventory.id))).to include(inventory)

    described_class.new.perform

    expect(Inventories::Availability.claimable(Inventory.where(id: inventory.id))).to include(inventory)
  end
end
