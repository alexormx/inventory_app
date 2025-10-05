require 'rails_helper'

RSpec.describe PurchaseOrders::RecalculateDistributedCostsForProductService, type: :service do
  let!(:product_a) { create(:product, length_cm: 10, width_cm: 2, height_cm: 3, weight_gr: 50, skip_seed_inventory: true) }
  let!(:product_b) { create(:product, length_cm: 5, width_cm: 2, height_cm: 2, weight_gr: 20, skip_seed_inventory: true) }
  let!(:po) { create(:purchase_order, shipping_cost: 30, tax_cost: 10, other_cost: 10, exchange_rate: 2) }

  before do
    PurchaseOrderItem.create!(purchase_order: po, product: product_a, quantity: 2, unit_cost: 10)
    PurchaseOrderItem.create!(purchase_order: po, product: product_b, quantity: 1, unit_cost: 5)
  end

  it 'recalculates distributed costs after product dimension change' do
    # Cambiamos las dimensiones del producto A para alterar el reparto volumétrico
    product_a.update!(length_cm: 20) # duplica volumen unitario

    result = described_class.new(product_a).call
    expect(result.purchase_orders_scanned).to be >= 1
    expect(result.items_recalculated).to be >= 2

    po.reload
    line_a = po.purchase_order_items.find_by(product_id: product_a.id)
    line_b = po.purchase_order_items.find_by(product_id: product_b.id)

    expect(line_a.total_line_volume).to be > 0
    expect(line_b.total_line_volume).to be > 0

    # Verifica que se hayan rellenado unit_additional_cost / unit_compose_cost
    expect(line_a.unit_additional_cost).not_to be_nil
    expect(line_b.unit_additional_cost).not_to be_nil
    expect(line_a.unit_compose_cost).to eq(line_a.unit_cost + line_a.unit_additional_cost)

    # Verifica propagación a piezas de inventario
    inv_items = Inventory.where(purchase_order_item_id: line_a.id)
    expect(inv_items.count).to eq(line_a.quantity)
    inv_items.each do |inv|
      expect(inv.purchase_cost.to_f).to eq(line_a.unit_compose_cost_in_mxn.to_f)
    end
  end
end
