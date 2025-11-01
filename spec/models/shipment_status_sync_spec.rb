require 'rails_helper'

RSpec.describe Shipment, type: :model do
  let(:user) { create(:user) }
  let(:sale_order) { create(:sale_order, user: user, status: "Pending", subtotal: 0, total_order_value: 0) }

  it "promotes sale_order to In Transit when shipment becomes shipped" do
    shipment = create(:shipment, sale_order: sale_order, status: :pending)
    expect(sale_order.reload.status).to eq("Pending")

    shipment.update!(status: :shipped)
    expect(sale_order.reload.status).to eq("In Transit")
  end

  it "promotes sale_order to Delivered when shipment becomes delivered" do
    shipment = create(:shipment, sale_order: sale_order, status: :pending)
    expect(sale_order.reload.status).to eq("Pending")

    shipment.update!(status: :delivered)
    expect(sale_order.reload.status).to eq("Delivered")
  end

  it "cancels sale_order when shipment is canceled (unless already delivered)" do
    shipment = create(:shipment, sale_order: sale_order, status: :pending)

    shipment.update!(status: :canceled)
    expect(sale_order.reload.status).to eq("Canceled")
  end

  it "does not downgrade a delivered sale_order when shipment changes to canceled" do
    so = create(:sale_order, user: user, status: "Delivered", total_order_value: 0)
    shipment = create(:shipment, sale_order: so, status: :pending)

    shipment.update!(status: :canceled)
    expect(so.reload.status).to eq("Delivered")
  end
end
