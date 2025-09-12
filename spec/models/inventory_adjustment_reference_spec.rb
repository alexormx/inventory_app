require 'rails_helper'

RSpec.describe InventoryAdjustment, type: :model do
  describe '#generate_reference_if_needed!' do
    it 'genera referencia con formato ADJ-YYYYMM-01 la primera vez del mes' do
      travel_to Time.zone.local(2025, 9, 12, 10, 0, 0) do
        adj = create(:inventory_adjustment)
        adj.generate_reference_if_needed!(Time.current)
        expect(adj.reference).to eq('ADJ-202509-01')
      end
    end

    it 'incrementa el consecutivo dentro del mismo mes' do
      travel_to Time.zone.local(2025, 9, 12, 11, 0, 0) do
        create(:inventory_adjustment, reference: 'ADJ-202509-01')
        adj = create(:inventory_adjustment)
        adj.generate_reference_if_needed!(Time.current)
        expect(adj.reference).to eq('ADJ-202509-02')
      end
    end

    it 'reinicia consecutivo en nuevo mes' do
      create(:inventory_adjustment, reference: 'ADJ-202508-09')
      travel_to Time.zone.local(2025, 9, 1, 0, 0, 0) do
        adj = create(:inventory_adjustment)
        adj.generate_reference_if_needed!(Time.current)
        expect(adj.reference).to eq('ADJ-202509-01')
      end
    end
  end
end
