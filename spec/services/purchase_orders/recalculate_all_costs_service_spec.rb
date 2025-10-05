require 'rails_helper'

RSpec.describe PurchaseOrders::RecalculateAllCostsService, type: :service do
  let!(:product1) { create(:product, skip_seed_inventory: true) }
  let!(:product2) { create(:product, skip_seed_inventory: true) }
  let!(:po1) { create(:purchase_order) }
  let!(:po2) { create(:purchase_order) }

  before do
    # Creamos items con columnas alpha_cost y compose_cost si existen
    if PurchaseOrderItem.column_names.include?("alpha_cost") && PurchaseOrderItem.column_names.include?("compose_cost")
      PurchaseOrderItem.create!(purchase_order: po1, product: product1, quantity: 2, unit_cost: 10, alpha_cost: 10, compose_cost: 10)
      PurchaseOrderItem.create!(purchase_order: po2, product: product2, quantity: 3, unit_cost: 5, alpha_cost: 5, compose_cost: 5)
    end
  end

  it 'runs without raising and returns a result struct' do
    service = described_class.new
    result = service.call
    expect(result).to respond_to(:products_scanned)
    expect(result).to respond_to(:items_scanned)
    expect(result).to respond_to(:items_updated)
    expect(result).to respond_to(:errors)
  end
end
