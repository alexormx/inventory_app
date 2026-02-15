require 'rails_helper'

RSpec.describe Shipment, type: :model do
  let(:user) { create(:user) }

  it "keeps sale_order as Delivered when shipment goes to shipped (no downgrade from Delivered)" do
    # Build order and get it to Delivered via proper shipment flow
    so = create(:sale_order, user: user, status: "Pending", subtotal: 0, total_order_value: 0)
    shipment = create(:shipment, sale_order: so, status: :pending)
    # Promote to Delivered by updating shipment
    shipment.update!(status: :delivered, tracking_number: 'TRACK123')
    expect(so.reload.status).to eq("Delivered")

    # shipped from Delivered: stays Delivered because sync only acts on Preparing/Confirmed
    shipment.update!(status: :shipped)
    expect(so.reload.status).to eq("Delivered")
  end

  it "downgrades sale_order to Preparing when shipment goes back to pending from shipped (In Transit)" do
    # Build properly: Preparing → shipped (In Transit) → pending (Preparing)
    so = create(:sale_order, user: user, status: "Pending", total_order_value: 100)
    create(:payment, sale_order: so, amount: 100, status: "Completed")
    so.reload
    shipment = create(:shipment, sale_order: so, status: :pending)
    # Use update_columns to set Preparing (bypass validation for test setup)
    so.update_columns(status: 'Preparing')
    # Ship it → sync promotes to In Transit
    shipment.update!(status: :shipped, tracking_number: 'TRACK123')
    expect(so.reload.status).to eq("In Transit")

    # Now rollback shipment to pending → should go to Preparing
    shipment.update!(status: :pending)
    expect(so.reload.status).to eq("Preparing")
  end

  it "does not downgrade past Preparing when shipment goes to pending from non-In Transit" do
    so = create(:sale_order, user: user, status: "Pending", total_order_value: 100)
    create(:payment, sale_order: so, amount: 50, status: "Completed")
    shipment = create(:shipment, sale_order: so, status: :pending)

    # SO is Pending, shipment pending → stays Pending
    shipment.update!(status: :pending)
    expect(so.reload.status).to eq("Pending")
  end
end
