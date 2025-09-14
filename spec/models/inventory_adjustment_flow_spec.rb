# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'InventoryAdjustment flow', type: :model do
  # Increase scenario: product starts with zero inventory
  let!(:product) { create(:product, skip_seed_inventory: true) }
  let!(:increase_adjustment) { create(:inventory_adjustment) }

  context 'increase lines' do
    before do
      create(:inventory_adjustment_line, inventory_adjustment: increase_adjustment, product: product, direction: 'increase', quantity: 2, unit_cost: 7.5)
    end

    it 'does not touch inventory in draft' do
      expect(Inventory.where(product: product).count).to eq(0)
    end

    it 'applies inventory when apply! called' do
      expect { increase_adjustment.apply!(applied_by: nil) }.to change { Inventory.where(product: product).count }.by(2)
      expect(increase_adjustment.reload.status).to eq('applied')
    end

    it 'is idempotent on second apply' do
      increase_adjustment.apply!
      expect { increase_adjustment.apply! }.not_to(change { Inventory.where(product: product).count })
    end

    it 'reverses created inventory' do
      increase_adjustment.apply!
      expect { increase_adjustment.reverse! }.to change { Inventory.where(product: product).count }.by(-2)
      expect(increase_adjustment.reload.status).to eq('draft')
    end

    it 'allows modifying line after reverse and reapplies new quantity' do
      increase_adjustment.apply!
      increase_adjustment.reverse!
      line = increase_adjustment.inventory_adjustment_lines.first
      line.update!(quantity: 4)
      expect { increase_adjustment.apply! }.to change { Inventory.where(product: product).count }.by(4)
    end
  end

  context 'decrease lines' do
    # Separate product with exactly 5 existing inventory units (no auto seed)
    let!(:product) { create(:product, skip_seed_inventory: true) }
    let!(:decrease_adjustment) { create(:inventory_adjustment) }
    let!(:existing_inventory) { create_list(:inventory, 5, product: product) }

    before do
      create(:inventory_adjustment_line, inventory_adjustment: decrease_adjustment, product: product, direction: 'decrease', quantity: 3, reason: 'scrap')
    end

    it 'marks items on apply' do
      decrease_adjustment.apply!
      expect(Inventory.where(product: product, status: :scrap).count).to eq(3)
    end

    it 'restores on reverse' do
      decrease_adjustment.apply!
      decrease_adjustment.reverse!
      expect(Inventory.where(product: product, status: :available).count).to eq(5)
    end
  end
end
