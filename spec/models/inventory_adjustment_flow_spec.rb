require 'rails_helper'

RSpec.describe 'InventoryAdjustment flow', type: :model do
  let!(:product) { create(:product) }
  let!(:adjustment) { create(:inventory_adjustment) }

  context 'increase lines' do
    before do
      create(:inventory_adjustment_line, inventory_adjustment: adjustment, product: product, direction: 'increase', quantity: 2, unit_cost: 7.5)
    end

    it 'does not touch inventory in draft' do
      expect(Inventory.where(product: product).count).to eq(0)
    end

    it 'applies inventory when apply! called' do
      expect { adjustment.apply!(applied_by: nil) }.to change { Inventory.where(product: product).count }.by(2)
      expect(adjustment.reload.status).to eq('applied')
    end

    it 'is idempotent on second apply' do
      adjustment.apply!
      expect { adjustment.apply! }.not_to change { Inventory.where(product: product).count }
    end

    it 'reverses created inventory' do
      adjustment.apply!
      expect { adjustment.reverse! }.to change { Inventory.where(product: product).count }.by(-2)
      expect(adjustment.reload.status).to eq('draft')
    end

    it 'allows modifying line after reverse and reapplies new quantity' do
      adjustment.apply!
      adjustment.reverse!
      line = adjustment.inventory_adjustment_lines.first
      line.update!(quantity: 4)
      expect { adjustment.apply! }.to change { Inventory.where(product: product).count }.by(4)
    end
  end

  context 'decrease lines' do
    let!(:existing_inventory) { create_list(:inventory, 5, product: product) }
    before do
      create(:inventory_adjustment_line, inventory_adjustment: adjustment, product: product, direction: 'decrease', quantity: 3, reason: 'scrap')
    end

    it 'marks items on apply' do
      adjustment.apply!
      expect(Inventory.where(product: product, status: :scrap).count).to eq(3)
    end

    it 'restores on reverse' do
      adjustment.apply!
      adjustment.reverse!
      expect(Inventory.where(product: product, status: :available).count).to eq(5)
    end
  end
end
