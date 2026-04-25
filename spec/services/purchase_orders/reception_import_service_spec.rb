require "rails_helper"

RSpec.describe PurchaseOrders::ReceptionImportService, type: :service do
  describe "#call" do
    it "creates a purchase order from resolved rows and records unresolved ones in notes" do
      supplier = create(:user, :supplier)
      product = create(:product, skip_seed_inventory: true, supplier_product_code: "TKT95078")
      parser = lambda do
        {
          document_currency: "JPY",
          invoice_date: "2026-01-13",
          invoice_number: "2186307",
          shipping_cost: 7858.to_d,
          other_cost: 2462.to_d,
          rows: [
            { supplier_product_code: "TKT95078", product_name: "Tomica", quantity: 2, unit_cost: 740.to_d },
            { supplier_product_code: "MISS-001", product_name: "Unknown", quantity: 1, unit_cost: nil }
          ],
          notes: ["OCR con confianza media"]
        }
      end
      resolver = lambda do |row|
        next OpenStruct.new(product: product, source: :product) if row[:supplier_product_code] == "TKT95078"

        nil
      end

      result = described_class.new(
        user: supplier,
        uploaded_file: double(original_filename: "invoice.png"),
        order_date: Date.current,
        expected_delivery_date: Date.current + 7.days,
        parser: parser,
        resolver: resolver,
        notes: "Recepción automática"
      ).call

      expect(result.purchase_order).to be_persisted
      expect(result.purchase_order.purchase_order_items.size).to eq(1)
      expect(result.purchase_order.purchase_order_items.first.product).to eq(product)
      expect(result.unresolved_rows.map { |row| row[:supplier_product_code] }).to eq(["MISS-001"])
      expect(result.purchase_order.notes).to include("MISS-001")
      expect(result.purchase_order.notes).to include("2186307")
      expect(result.purchase_order.currency).to eq("JPY")
      expect(result.purchase_order.shipping_cost).to eq(7858.to_d)
      expect(result.purchase_order.other_cost).to eq(2462.to_d)
    end
  end
end