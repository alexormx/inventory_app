require 'rails_helper'

RSpec.describe Products::UpdateStatsService, type: :service do
  let(:product) { create(:product) }
  let(:purchase_order) { create(:purchase_order) }
  let!(:purchase_item) { create(:purchase_order_item, product: product, purchase_order: purchase_order, quantity: 5, unit_cost: 10.0, unit_additional_cost: 0) }
  let(:sale_order) { create(:sale_order) }
  let!(:shipment) { create(:shipment, sale_order: sale_order) }
  let!(:payment) { create(:payment, sale_order: sale_order) }
  before { sale_order.update!(status: 'Shipped') }
  let!(:sale_item) { create(:sale_order_item, product: product, sale_order: sale_order, quantity: 2, unit_final_price: 20.0, unit_cost: 20.0) }

  it 'updates product stats based on related items' do
    described_class.new(product).call
    product.reload

    expect(product.total_purchase_quantity).to eq(5)
    expect(product.total_sales_quantity).to eq(2)
    expect(product.total_purchase_value).to eq(50)
    expect(product.total_sales_value).to eq(40)
    expect(product.average_purchase_cost).to eq(10)
    expect(product.average_sales_price).to eq(20)
    expect(product.total_purchase_order).to eq(1)
    expect(product.total_sales_order).to eq(1)
    expect(product.total_units_sold).to eq(2)
  end
end
