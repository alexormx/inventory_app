require 'rails_helper'

RSpec.describe InventoryServices::AvailabilitySplitter, type: :service do
  let(:product) { create(:product, preorder_available: false, backorder_allowed: false) }

  context 'sin stock (on_hand=0) y sin preorder/backorder' do
    it 'marca todo pending sin tipo => consumidor decide error' do
  splitter = described_class.new(product, 5)
      allow(product).to receive(:current_on_hand).and_return(0)
      r = splitter.call
      expect(r.immediate).to eq(0)
      expect(r.pending).to eq(5)
      expect(r.pending_type).to be_nil
    end
  end

  context 'con stock parcial' do
    it 'divide immediate y pending' do
      allow(product).to receive(:current_on_hand).and_return(3)
      r = described_class.new(product, 5).call
      expect(r.immediate).to eq(3)
      expect(r.pending).to eq(2)
    end
  end

  context 'preorder habilitado' do
    let(:product) { create(:product, preorder_available: true, backorder_allowed: false) }
    it 'asigna pending_type :preorder si falta stock' do
      allow(product).to receive(:current_on_hand).and_return(1)
      r = described_class.new(product, 4).call
      expect(r.pending_type).to eq(:preorder)
      expect(r.pending).to eq(3)
    end
  end

  context 'backorder habilitado' do
    let(:product) { create(:product, preorder_available: false, backorder_allowed: true) }
    it 'asigna pending_type :backorder' do
      allow(product).to receive(:current_on_hand).and_return(0)
      r = described_class.new(product, 2).call
      expect(r.pending_type).to eq(:backorder)
    end
  end
end
