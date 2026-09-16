# frozen_string_literal: true

require 'rails_helper'

# CHARACTERIZATION, not a statement of desired behaviour.
#
# PR A0 made every customer-facing storefront surface condition-aware. The
# preorder supply path was deliberately left alone: Preorders::PreorderAllocator
# counts supply as Inventory.customer_sellable WITHOUT an item_condition
# filter, so a collectible piece counts as supply for brand_new preorder
# demand. Preorder demand is only ever raised for brand_new
# (InventoryServices::AvailabilitySplitter sets pending_type for brand_new
# only), so that is a real condition-blindness bug.
#
# It is NOT fixed here: correcting it means deciding how existing preorder
# demand maps onto conditions and touching the allocator's locking, which
# would turn this PR into a preorder rewrite. These examples pin the current
# behaviour so the follow-up changes it deliberately and visibly.
RSpec.describe 'Preorder supply condition handling (characterization)' do
  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true, preorder_available: true) }

  def located_available(condition:)
    create(:inventory, product: product, status: :available,
                       item_condition: condition, inventory_location: location)
  end

  it 'counts a collectible piece as preorder supply, ignoring condition' do
    located_available(condition: :mint)

    supply = Inventory.customer_sellable.where(product_id: product.id).count

    # Condition-blind on purpose here: this is the documented current state.
    expect(supply).to eq(1)
    # While the canonical storefront rule correctly reports no brand_new.
    expect(Inventories::Availability.for(product, condition: 'brand_new').available_now).to eq(0)
  end

  it 'still counts in-transit stock as preorder supply' do
    purchase_order = create(:purchase_order, expected_delivery_date: 5.days.from_now.to_date)
    create(:inventory, product: product, status: :in_transit,
                       item_condition: :brand_new, purchase_order: purchase_order)

    expect(Inventory.customer_sellable.where(product_id: product.id).count).to eq(1)
    expect(Inventories::Availability.for(product, condition: 'brand_new').in_transit).to eq(1)
  end

  it 'keeps the splitter cascade: on-hand, then in-transit, then preorder' do
    located_available(condition: :brand_new)

    result = InventoryServices::AvailabilitySplitter.new(product, 3, condition: 'brand_new').call

    expect(result.immediate).to eq(1)
    expect(result.pending).to eq(2)
    expect(result.pending_type).to eq(:preorder)
  end
end
