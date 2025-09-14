# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'InventoryAdjustment multiple lines same product' do
  it 'applies multiple increase and decrease lines for same product' do
    product = create(:product, skip_seed_inventory: true)
    create_list(:inventory, 5, product: product, status: :available)

    adjustment = create(:inventory_adjustment)
    create(:inventory_adjustment_line, inventory_adjustment: adjustment, product: product, quantity: 2, direction: 'decrease', reason: 'damaged')
    create(:inventory_adjustment_line, inventory_adjustment: adjustment, product: product, quantity: 1, direction: 'decrease', reason: 'lost')
    create(:inventory_adjustment_line, inventory_adjustment: adjustment, product: product, quantity: 3, direction: 'increase', reason: 'scrap', unit_cost: 4.5)

    movements = adjustment.apply!(now: Time.zone.local(2025, 9, 12, 13, 0, 0))
    expect(movements).to eq(6) # 3 decreases act on existing, 3 increases create

    product.reload
    # 5 initial available - 3 decreased + 3 increased => 5 available again (some changed status)
    expect(product.inventories.count).to eq(8) # 5 original + 3 new
    expect(product.inventories.where(status: :damaged).count + product.inventories.where(status: :lost).count).to eq(3)
    expect(product.inventories.where(source: 'ledger_adjustment').count).to eq(3)
  end
end
