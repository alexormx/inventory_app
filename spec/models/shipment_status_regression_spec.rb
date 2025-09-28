require 'rails_helper'

RSpec.describe Shipment, type: :model do
  let(:user) { create(:user) }
  let(:sale_order) { create(:sale_order, user: user, status: "Delivered", total_order_value: 0) }

  it "downgrades sale_order from Delivered to In Transit when shipment goes to shipped" do
    shipment = create(:shipment, sale_order: sale_order, status: :delivered)
    expect(sale_order.reload.status).to eq("Delivered")

    shipment.update!(status: :shipped)
    expect(sale_order.reload.status).to eq("In Transit")
  end

  it "downgrades sale_order to Confirmed when shipment goes back to pending and order is fully paid" do
    so = create(:sale_order, user: user, status: "In Transit", total_order_value: 100)
    create(:payment, sale_order: so, amount: 100, status: "Completed")
    shipment = create(:shipment, sale_order: so, status: :shipped)

    expect(so.reload.status).to eq("In Transit")

    shipment.update!(status: :pending)
    expect(so.reload.status).to eq("Confirmed")
  end

  it "downgrades sale_order to Pending when shipment goes back to pending and order is not fully paid" do
    so = create(:sale_order, user: user, status: "In Transit", total_order_value: 100)
    create(:payment, sale_order: so, amount: 50, status: "Completed")
    shipment = create(:shipment, sale_order: so, status: :shipped)

    shipment.update!(status: :pending)
    expect(so.reload.status).to eq("Pending")
  end
end
