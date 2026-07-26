# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryServices::AvailabilitySplitter do
  let(:product) do
    create(
      :product,
      skip_seed_inventory: true,
      preorder_available: false,
      backorder_allowed: false
    )
  end
  let(:location) { create(:inventory_location) }

  it 'uses one sellable rule and item condition for the availability split' do
    create(:inventory, product: product, status: :available, item_condition: :brand_new, inventory_location: location)
    create(:inventory, product: product, status: :in_transit, item_condition: :brand_new)
    create(:inventory, product: product, status: :available, item_condition: :brand_new, inventory_location: nil)
    create(:inventory, product: product, status: :available, item_condition: :mint, inventory_location: location)
    assigned = create(:inventory, product: product, status: :available, item_condition: :brand_new, inventory_location: location)
    assigned.update_columns(sale_order_id: create(:sale_order).id)

    split = described_class.new(
      product,
      4,
      condition: 'brand_new'
    ).call

    expect(product.current_on_hand(condition: 'brand_new')).to eq(1)
    expect(product.in_transit_count(condition: 'brand_new')).to eq(1)
    expect(split.immediate).to eq(1)
    expect(split.in_transit_qty).to eq(1)
    expect(split.pending).to eq(2)
    expect(split.pending_type).to be_nil
  end
end
