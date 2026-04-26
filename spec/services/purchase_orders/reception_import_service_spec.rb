require "rails_helper"

RSpec.describe PurchaseOrders::ReceptionImportService, type: :service do
  describe "#call" do
    it "creates a purchase order from per-row decisions and notes the skipped ones" do
      supplier = create(:user, :supplier)
      product = create(:product, skip_seed_inventory: true, supplier_product_code: "TKT95078")

      decisions = [
        { idx: 0, action: "use_existing", product_id: product.id, supplier_product_code: "TKT95078",
          quantity: 2, unit_cost: 740.to_d, product_name: "Tomica" },
        { idx: 1, action: "skip", supplier_product_code: "MISS-001", quantity: 1, unit_cost: nil,
          product_name: "Unknown" }
      ]

      result = described_class.new(
        user: supplier,
        decisions: decisions,
        document_metadata: {
          document_currency: "JPY",
          invoice_date: "2026-01-13",
          invoice_number: "2186307",
          shipping_cost: 7858.to_d,
          other_cost: 2462.to_d,
          notes: ["OCR con confianza media"]
        },
        order_date: Date.current,
        expected_delivery_date: Date.current + 7.days,
        notes: "Recepción automática",
        uploaded_filename: "invoice.png"
      ).call

      expect(result.purchase_order).to be_persisted
      expect(result.purchase_order.purchase_order_items.size).to eq(1)
      expect(result.purchase_order.purchase_order_items.first.product).to eq(product)
      expect(result.purchase_order.notes).to include("2186307")
      expect(result.purchase_order.notes).to include("invoice.png")
      expect(result.purchase_order.currency).to eq("JPY")
      expect(result.purchase_order.shipping_cost).to eq(7858.to_d)
      expect(result.purchase_order.other_cost).to eq(2462.to_d)
    end

    it "syncs a catalog item when the decision is sync_catalog" do
      supplier = create(:user, :supplier)
      catalog_item = create(:supplier_catalog_item, product: nil, supplier_product_code: "TKT99999")

      decisions = [
        { idx: 0, action: "sync_catalog", catalog_item_id: catalog_item.id,
          supplier_product_code: "TKT99999", quantity: 1, unit_cost: 500.to_d, product_name: catalog_item.canonical_name }
      ]

      result = described_class.new(
        user: supplier,
        decisions: decisions,
        document_metadata: { document_currency: "JPY" },
        order_date: Date.current,
        expected_delivery_date: Date.current + 7.days
      ).call

      expect(result.purchase_order.purchase_order_items.size).to eq(1)
      created_product = result.purchase_order.purchase_order_items.first.product
      expect(created_product.supplier_product_code).to eq("TKT99999")
      expect(catalog_item.reload.product).to eq(created_product)
    end

    it "raises ImportError when no decision yields a product" do
      supplier = create(:user, :supplier)
      decisions = [
        { idx: 0, action: "skip", supplier_product_code: "MISS-001", quantity: 1, unit_cost: nil, product_name: "" }
      ]

      expect {
        described_class.new(
          user: supplier,
          decisions: decisions,
          order_date: Date.current,
          expected_delivery_date: Date.current + 7.days
        ).call
      }.to raise_error(PurchaseOrders::ReceptionImportService::ImportError)
    end
  end
end
