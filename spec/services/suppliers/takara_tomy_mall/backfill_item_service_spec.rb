# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::TakaraTomyMall::BackfillItemService do
  let(:catalog_item) { create(:supplier_catalog_item, image_urls: ["https://www.hlj.com/productimages/tkt/tkt95078_0.jpg"], description_raw: nil) }
  let(:document) do
    Nokogiri::HTML(<<~HTML)
      <html>
        <head>
          <meta property="og:title" content="トミカ No.43 ランボルギーニ テメラリオ">
          <meta name="description" content="公式の商品説明です。">
          <script type="application/ld+json">
            {"@type":"Product","name":"トミカ No.43 ランボルギーニ テメラリオ","description":"公式の商品説明です。","image":["https://takaratomymall.jp/images/item_1.jpg"]}
          </script>
        </head>
        <body>
          <dl><dt>シリーズ</dt><dd>トミカ</dd></dl>
        </body>
      </html>
    HTML
  end
  let(:fetch_result) do
    Suppliers::TakaraTomyMall::FetchDocumentService::Result.new(
      document: document,
      status: 200,
      url: "https://takaratomymall.jp/shop/g/g4904810950783/"
    )
  end

  before do
    allow(Suppliers::TakaraTomyMall::FetchDocumentService).to receive(:new).and_return(instance_double(Suppliers::TakaraTomyMall::FetchDocumentService, call: fetch_result))
  end

  it "creates or updates the Takara source and enriches the catalog item" do
    result = described_class.new(catalog_item).call

    expect(result.changed).to be true
    source = catalog_item.reload.source_for("takaratomy_mall")
    expect(source).to be_present
    expect(source.fetch_status).to eq("ok")
    expect(source.image_urls).to include("https://takaratomymall.jp/images/item_1.jpg")
    expect(catalog_item.image_urls).to include("https://takaratomymall.jp/images/item_1.jpg")
    expect(catalog_item.description_raw).to eq("公式の商品説明です。")
    expect(catalog_item.details_payload.dig("takara_tomy_mall", "series")).to eq("トミカ")
    expect(catalog_item.needs_review).to be true
  end
end