require "rails_helper"

RSpec.describe PurchaseOrders::ReceptionDocumentParserService, type: :service do
  describe "#call" do
    it "normaliza el formato real de invoice HLJ con cargos y supplier code dentro de Description" do
      uploaded_file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test1.png"), "image/png")
      client = instance_double(OpenAI::Client)

      allow(client).to receive(:chat).and_return(
        {
          "choices" => [
            {
              "message" => {
                "content" => {
                  document_currency: "JPY",
                  invoice_date: "2026/01/13",
                  invoice_number: "2186307",
                  subtotal: "74,202",
                  shipping_cost: "7,858",
                  other_cost: "2,462",
                  document_total: "84,522",
                  rows: [
                    {
                      supplier_product_code: "TMT33336",
                      product_name: "LV-N Ferrari F40 (1989) (Red)",
                      barcode: "4543736333364",
                      quantity: 2,
                      unit_cost: "6,224",
                      confidence: 0.99
                    }
                  ],
                  notes: ["Formato HLJ invoice"]
                }.to_json
              }
            }
          ]
        }
      )

      result = described_class.new(uploaded_file, client: client).call

      expect(result[:document_currency]).to eq("JPY")
      expect(result[:invoice_date]).to eq("2026-01-13")
      expect(result[:invoice_number]).to eq("2186307")
      expect(result[:subtotal]).to eq(74202.to_d)
      expect(result[:shipping_cost]).to eq(7858.to_d)
      expect(result[:other_cost]).to eq(2462.to_d)
      expect(result[:document_total]).to eq(84522.to_d)
      expect(result[:rows]).to eq([
        {
          supplier_product_code: "TMT33336",
          product_name: "LV-N Ferrari F40 (1989) (Red)",
          barcode: "4543736333364",
          quantity: 2,
          unit_cost: 6224.to_d,
          confidence: 0.99
        }
      ])
    end
  end
end