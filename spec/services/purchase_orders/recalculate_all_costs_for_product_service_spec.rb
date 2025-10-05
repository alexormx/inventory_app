require 'rails_helper'

RSpec.describe PurchaseOrders::RecalculateAllCostsForProductService, type: :service do
  let!(:product) { create(:product, length_cm: 10, width_cm: 2, height_cm: 3, weight_gr: 50, skip_seed_inventory: true) }
  let!(:other_product) { create(:product, length_cm: 5, width_cm: 2, height_cm: 2, weight_gr: 20, skip_seed_inventory: true) }
  let!(:po) { create(:purchase_order, shipping_cost: 30, tax_cost: 10, other_cost: 10, exchange_rate: 2) }

  before do
    PurchaseOrderItem.create!(purchase_order: po, product: product, quantity: 2, unit_cost: 10)
    PurchaseOrderItem.create!(purchase_order: po, product: other_product, quantity: 1, unit_cost: 5)
  end

  it 'runs unified recalculation and logs event when dimension_change flag is true' do
    result = described_class.new(product, dimension_change: true).call
    expect(result.distributed_purchase_orders_scanned).to be >= 1
    expect(result.distributed_items_recalculated).to be >= 2
    expect(result.errors).to be_empty

    po.reload
    line = po.purchase_order_items.find_by(product_id: product.id)
    expect(line.unit_compose_cost.to_f).to eq(line.unit_cost.to_f + line.unit_additional_cost.to_f)

    inv_items = Inventory.where(purchase_order_item_id: line.id)
    inv_items.each do |inv|
      expect(inv.purchase_cost.to_f).to eq(line.unit_compose_cost_in_mxn.to_f)
    end

    evt = InventoryEvent.where(event_type: 'product_dimensions_changed', product_id: product.id).last
    expect(evt).not_to be_nil
    expect(evt.metadata['distributed_items_recalculated']).to be >= 2
  end
end
