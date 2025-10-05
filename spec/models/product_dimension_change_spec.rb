require 'rails_helper'

RSpec.describe 'Product dimension change recalculation', type: :model do
  let!(:product) { create(:product, length_cm: 10, width_cm: 2, height_cm: 3, weight_gr: 50, skip_seed_inventory: true) }
  let!(:other_product) { create(:product, length_cm: 5, width_cm: 2, height_cm: 2, weight_gr: 20, skip_seed_inventory: true) }
  let!(:po) { create(:purchase_order, shipping_cost: 30, tax_cost: 10, other_cost: 10, exchange_rate: 2) }

  before do
    PurchaseOrderItem.create!(purchase_order: po, product: product, quantity: 2, unit_cost: 10)
    PurchaseOrderItem.create!(purchase_order: po, product: other_product, quantity: 1, unit_cost: 5)
  end

  it 'triggers distributed cost recalculation via product callback when dimensions change' do
    original_line = po.purchase_order_items.find_by(product_id: product.id)
    expect(original_line.total_line_volume.to_f).to be > 0

    # Cambiamos dimensiones para duplicar volumen unitario
    expect {
      product.update!(length_cm: product.length_cm * 2)
    }.to change { product.reload.length_cm }

    # Forzamos reload de la PO y líneas
    po.reload
    updated_line = po.purchase_order_items.find_by(product_id: product.id)

    expect(updated_line.total_line_volume.to_f).to be > original_line.total_line_volume.to_f
    expect(updated_line.unit_additional_cost.to_f).to be >= 0
    expect(updated_line.unit_compose_cost.to_f).to eq((updated_line.unit_cost.to_f + updated_line.unit_additional_cost.to_f).round(2))
    # Confirmar propagación a inventario
    Inventory.where(purchase_order_item_id: updated_line.id).each do |inv|
      expect(inv.purchase_cost.to_f).to eq(updated_line.unit_compose_cost_in_mxn.to_f)
    end
  end
end
