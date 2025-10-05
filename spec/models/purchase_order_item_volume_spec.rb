require 'rails_helper'

RSpec.describe PurchaseOrderItem, type: :model do
  let(:product) { create(:product, length_cm: 10, width_cm: 2, height_cm: 3, weight_gr: 50, skip_seed_inventory: true) }
  let(:po) { create(:purchase_order) }

  it 'computes total_line_volume and total_line_weight before validation' do
    item = PurchaseOrderItem.new(purchase_order: po, product: product, quantity: 4, unit_cost: 10)
    expect(item.total_line_volume).to be_nil
    expect(item.total_line_weight).to be_nil
    item.valid?
    expect(item.total_line_volume).to eq(4 * product.unit_volume_cm3.to_f)
    expect(item.total_line_weight).to eq(4 * product.weight_gr.to_f)
  end

  it 'recomputes when quantity changes' do
    item = PurchaseOrderItem.create!(purchase_order: po, product: product, quantity: 2, unit_cost: 10)
    original_volume = item.total_line_volume
    item.update!(quantity: 5)
    expect(item.total_line_volume).to eq(5 * product.unit_volume_cm3.to_f)
    expect(item.total_line_volume).not_to eq(original_volume)
  end
end
