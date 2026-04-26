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

  describe "POST /admin/purchase_orders/preview_reception" do
    it "parses the document and renders the review page" do
      sign_in admin
      parser_double = instance_double(
        PurchaseOrders::ReceptionDocumentParserService,
        call: {
          document_currency: "JPY",
          invoice_date: "2026-01-13",
          invoice_number: "2186307",
          subtotal: 1000.to_d,
          shipping_cost: 100.to_d,
          other_cost: 0.to_d,
          document_total: 1100.to_d,
          rows: [
            { supplier_product_code: "TKT95078", product_name: "Tomica", barcode: nil, quantity: 1, unit_cost: 500.to_d, confidence: 0.95 }
          ],
          notes: []
        }
      )
      allow(PurchaseOrders::ReceptionDocumentParserService).to receive(:new).and_return(parser_double)

      post preview_reception_admin_purchase_orders_path, params: {
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

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("TKT95078")
    end
  end

  describe "POST /admin/purchase_orders/commit_reception" do
    it "creates a purchase order from the per-row decisions and redirects to edit" do
      sign_in admin
      purchase_order = create(:purchase_order, user: supplier)
      result = PurchaseOrders::ReceptionImportService::Result.new(
        purchase_order: purchase_order,
        resolved_rows: [{ supplier_product_code: "TKT95078" }],
        unresolved_rows: []
      )
      service = instance_double(PurchaseOrders::ReceptionImportService, call: result)
      allow(PurchaseOrders::ReceptionImportService).to receive(:new).and_return(service)

      post commit_reception_admin_purchase_orders_path, params: {
        reception: {
          user_id: supplier.id,
          order_date: Date.current,
          expected_delivery_date: Date.current + 7.days,
          status: "Pending",
          currency: "JPY",
          exchange_rate: 1,
          notes: "Recepción"
        },
        decisions: {
          "0" => {
            action: "use_existing",
            supplier_product_code: "TKT95078",
            product_id: product.id,
            quantity: 1,
            unit_cost: 500,
            product_name: "Tomica"
          }
        }
      }

      expect(response).to redirect_to(edit_admin_purchase_order_path(purchase_order))
    end
  end

  describe "GET /admin/purchase_orders/:id" do
    it "renders even when a line has nil total_line_cost_in_mxn" do
      sign_in admin
      purchase_order = create(:purchase_order, user: supplier)
      create(
        :purchase_order_item,
        purchase_order: purchase_order,
        product: product,
        quantity: 2,
        unit_cost: 100,
        total_line_cost_in_mxn: nil
      )

      get admin_purchase_order_path(purchase_order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(purchase_order.id)
    end
  end
end
