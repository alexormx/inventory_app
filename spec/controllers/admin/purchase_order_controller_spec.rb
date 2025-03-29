require 'rails_helper'

RSpec.describe Admin::PurchaseOrdersController, type: :controller do
  let(:admin) { create(:user, role: :admin) }
  let(:product) { create(:product) }

  before { sign_in admin }

  describe "POST create" do
    it "creates a purchase order with items" do
      expect {
        post :create, params: {
          purchase_order: {
            user_id: create(:user, role: :supplier).id,
            order_date: Date.today,
            subtotal: 100.0,
            tax_cost: 10.0,
            currency: "MXN",
            shipping_cost: 5.0,
            other_cost: 2.0,
            expected_delivery_date: Date.today + 7.days,
            status: "Pending",
            notes: "Test order",
            total_order_cost: 117.0,
            total_cost_mxn: 117.0,
            actual_delivery_date: Date.today + 7.days,
            exchange_rate: 1.0,
            total_volume: 50.0,
            total_weight: 35.0,

            purchase_order_items_attributes: {
              "0" => {
                product_id: product.id,
                quantity: 2,
                unit_cost: 50.0 
              }
            }
          }
        }
      }.to change(PurchaseOrderItem, :count).by(1)
    end
  end
end
