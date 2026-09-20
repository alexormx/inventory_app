# frozen_string_literal: true

require 'rails_helper'

# Preorder supply is condition-scoped.
#
# PR A0 made every customer-facing storefront surface condition-aware but
# deliberately left the preorder path alone, and this file pinned that gap as a
# characterization. The follow-up closed it: Preorders::PreorderAllocator now
# budgets supply PER CONDITION, so a collectible piece can no longer authorise
# or be spent on brand_new preorder demand.
#
# What deliberately did NOT change:
#
#   * Inventory#customer_sellable keeps its broader meaning - free stock that is
#     available-now OR in-transit. It is the allocator/preorder supply rule and
#     is intentionally condition-agnostic on its own; callers compose it with
#     #for_condition (or the allocator's per-condition budget).
#   * Same-condition in-transit stock still counts as preorder supply.
#   * The splitter cascade (on-hand, then in-transit, then preorder).
RSpec.describe 'Preorder supply condition handling' do
  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true, preorder_available: true) }

  def located_available(condition:)
    create(:inventory, product: product, status: :available,
                       item_condition: condition, inventory_location: location)
  end

  it 'keeps customer_sellable condition-agnostic on its own' do
    located_available(condition: :mint)

    # The scope itself still counts the piece: its job is "free stock, now or
    # incoming", not "stock of condition X". Condition scoping is the caller's.
    expect(Inventory.customer_sellable.where(product_id: product.id).count).to eq(1)
    # The canonical storefront rule correctly reports no brand_new.
    expect(Inventories::Availability.for(product, condition: 'brand_new').available_now).to eq(0)
  end

  it 'does not let a collectible piece satisfy brand_new preorder demand' do
    order = create(:sale_order)
    line = create(
      :sale_order_item,
      sale_order: order, product: product,
      quantity: 1, preorder_quantity: 1, item_condition: :brand_new,
      unit_cost: 40, unit_selling_price: 100, unit_final_price: 100, total_line_cost: 40
    )
    reservation = create(
      :preorder_reservation,
      product: product, user: order.user, sale_order: order,
      sale_order_item: line, quantity: 1
    )
    mint = located_available(condition: :mint)

    expect(Preorders::PreorderAllocator.new(product).call).to eq(0)
    expect(reservation.reload).to be_pending
    expect(mint.reload.sale_order_item_id).to be_nil
  end

  it 'still counts same-condition in-transit stock as preorder supply' do
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
