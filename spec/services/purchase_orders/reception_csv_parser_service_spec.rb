require "rails_helper"

RSpec.describe PurchaseOrders::ReceptionCsvParserService, type: :service do
  describe "#call" do
    let(:uploaded_file) do
      Rack::Test::UploadedFile.new(
        Rails.root.join("spec/fixtures/files/tkg_invoice_sample.csv"),
        "text/csv"
      )
    end

    it "parses items, aggregates duplicates, strips JanCode whitespace, and reads the totals row" do
      result = described_class.new(uploaded_file).call

      expect(result[:document_currency]).to eq("JPY")
      expect(result[:subtotal]).to eq(8296.to_d)
      expect(result[:shipping_cost]).to eq(500.to_d)
      expect(result[:other_cost]).to eq(150.to_d)
      expect(result[:document_total]).to eq(8946.to_d)
      expect(result[:rows].size).to eq(2)

      first = result[:rows].find { |r| r[:supplier_product_code] == "TKT95083" }
      expect(first[:quantity]).to eq(12)
      expect(first[:unit_cost]).to eq(408.to_d)
      expect(first[:barcode]).to eq("4904810950905")

      aggregated = result[:rows].find { |r| r[:supplier_product_code] == "TKT99536" }
      expect(aggregated[:quantity]).to eq(5) # 2 + 3
      expect(aggregated[:unit_cost]).to eq(680.to_d)
    end

    it "raises when required columns are missing" do
      tmp = Tempfile.new(["bad", ".csv"])
      tmp.write("Foo,Bar\n1,2\n")
      tmp.rewind
      file = Rack::Test::UploadedFile.new(tmp.path, "text/csv")

      expect { described_class.new(file).call }
        .to raise_error(PurchaseOrders::ReceptionCsvParserService::ParseError, /Columnas faltantes/)
    end
  end
end
