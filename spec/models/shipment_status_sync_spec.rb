require 'rails_helper'

RSpec.describe Shipment, type: :model do
  let(:user) { create(:user) }

  it "promotes sale_order to In Transit when shipment becomes shipped from Preparing" do
    so = create(:sale_order, user: user, status: "Pending", subtotal: 0, total_order_value: 0)
    shipment = create(:shipment, sale_order: so, status: :pending)
    so.update_columns(status: 'Preparing') # set up for test

    shipment.update!(status: :shipped, tracking_number: 'TRACK123')
    expect(so.reload.status).to eq("In Transit")
  end

  it "promotes sale_order to In Transit when shipment becomes shipped from Confirmed" do
    so = create(:sale_order, user: user, status: "Confirmed", subtotal: 0, total_order_value: 0)
    shipment = create(:shipment, sale_order: so, status: :pending)

    shipment.update!(status: :shipped, tracking_number: 'TRACK123')
    expect(so.reload.status).to eq("In Transit")
  end

  it "promotes sale_order to Delivered when shipment becomes delivered" do
    so = create(:sale_order, user: user, status: "Confirmed", subtotal: 0, total_order_value: 0)
    shipment = create(:shipment, sale_order: so, status: :pending)

    shipment.update!(status: :delivered, tracking_number: 'TRACK123')
    expect(so.reload.status).to eq("Delivered")
  end

  it "cancels sale_order when shipment is canceled (unless already delivered)" do
    so = create(:sale_order, user: user, status: "Confirmed", subtotal: 0, total_order_value: 0)
    shipment = create(:shipment, sale_order: so, status: :pending)

    shipment.update!(status: :canceled)
    expect(so.reload.status).to eq("Canceled")
  end

  it "does not downgrade a delivered sale_order when shipment changes to canceled" do
    so = create(:sale_order, user: user, status: "Pending", subtotal: 0, total_order_value: 0)
    shipment = create(:shipment, sale_order: so, status: :pending)
    shipment.update!(status: :delivered, tracking_number: 'TRACK123')
    expect(so.reload.status).to eq("Delivered")

    shipment.update!(status: :canceled)
    expect(so.reload.status).to eq("Delivered")
  end
end
