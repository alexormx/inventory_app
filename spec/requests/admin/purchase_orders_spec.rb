require 'rails_helper'

RSpec.describe "Admin Purchase Orders", type: :request do
  before(:all) { Rails.application.reload_routes! }
  let(:admin) { create(:user, role: :admin) }
  let(:supplier) { create(:user, role: :supplier) }
  let(:product) { create(:product) }

  describe "POST /admin/purchase_orders" do
    it "creates a purchase order with items" do
      sign_in admin
      expect {
        post admin_purchase_orders_path, params: {
          purchase_order: {
            user_id: supplier.id,
            order_date: Date.today,
            expected_delivery_date: Date.today + 7.days,
            subtotal: 100.0,
            tax_cost: 10.0,
            currency: "MXN",
            shipping_cost: 5.0,
            other_cost: 2.0,
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
      # also ensure redirect on success
      expect(response).to redirect_to(admin_purchase_orders_path)
    end
  end

  describe "POST /admin/purchase_orders/import_reception" do
    it "creates a purchase order through the reception importer and redirects to edit" do
      sign_in admin
      purchase_order = create(:purchase_order, user: supplier)
      result = PurchaseOrders::ReceptionImportService::Result.new(
        purchase_order: purchase_order,
        resolved_rows: [{ supplier_product_code: "TKT95078" }],
        unresolved_rows: [{ supplier_product_code: "MISS-001" }]
      )
      service = instance_double(PurchaseOrders::ReceptionImportService, call: result)

      allow(PurchaseOrders::ReceptionImportService).to receive(:new).and_return(service)

      post import_reception_admin_purchase_orders_path, params: {
        reception: {
          user_id: supplier.id,
          order_date: Date.current,
          expected_delivery_date: Date.current + 7.days,
          status: "Pending",
          currency: "JPY",
          exchange_rate: 1,
          notes: "Recepción"
        },
        document: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test1.png"), "image/png")
      }

      expect(response).to redirect_to(edit_admin_purchase_order_path(purchase_order))
    end
  end
end
