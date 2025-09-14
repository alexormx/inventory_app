# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplyInventoryAdjustmentService do
  it 'asigna adjustment_reference a inventarios creados y modificados' do
    product = create(:product, skip_seed_inventory: true)
    # Inventario existente para decrease
    existing = create(:inventory, product: product, status: :available)

    adjustment = create(:inventory_adjustment)
    create(:inventory_adjustment_line, inventory_adjustment: adjustment, product: product, quantity: 2, direction: 'increase', reason: 'scrap')
  create(:inventory_adjustment_line, inventory_adjustment: adjustment, product: product, quantity: 1, direction: 'decrease',
                                       reason: 'damaged')

    service = described_class.new(adjustment, applied_by: nil, now: Time.zone.local(2025, 9, 12, 12, 0, 0))
    service.call

    adjustment.reload
    expect(adjustment.reference).to match(/ADJ-202509-\d{2}/)

    created_inventories = Inventory.where(product: product, source: 'ledger_adjustment')
    expect(created_inventories.count).to eq(2)
    created_inventories.each do |inv|
      expect(inv.adjustment_reference).to eq(adjustment.reference)
    end

    existing.reload
    expect(existing.adjustment_reference).to eq(adjustment.reference)
    expect(existing.status).to eq('damaged')
  end
end
