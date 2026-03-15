# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::TakaraTomyMall::ExtractProductDetailsService do
  subject(:payload) { described_class.new(document, source_url: source_url, barcode: "4904810950783").call }

  let(:source_url) { "https://takaratomymall.jp/shop/g/g4904810950783/" }
  let(:document) do
    Nokogiri::HTML(<<~HTML)
      <html>
        <head>
          <meta property="og:title" content="トミカ No.43 ランボルギーニ テメラリオ">
          <meta name="description" content="タカラトミーモール公式の商品説明です。">
          <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "Product",
              "name": "トミカ No.43 ランボルギーニ テメラリオ",
              "description": "タカラトミーモール公式の商品説明です。",
              "brand": { "@type": "Brand", "name": "タカラトミー" },
              "image": [
                "https://takaratomymall.jp/images/item_1.jpg",
                "https://takaratomymall.jp/images/item_2.jpg"
              ]
            }
          </script>
        </head>
        <body>
          <dl>
            <dt>シリーズ</dt><dd>トミカ</dd>
            <dt>スケール</dt><dd>1/64</dd>
            <dt>材質</dt><dd>ダイキャスト</dd>
            <dt>発売日</dt><dd>2026年2月21日</dd>
          </dl>
          <img src="https://takaratomymall.jp/images/detail_extra.jpg">
        </body>
      </html>
    HTML
  end

  it "extracts title, description, images and normalized data" do
    expect(payload[:title]).to eq("トミカ No.43 ランボルギーニ テメラリオ")
    expect(payload[:description]).to eq("タカラトミーモール公式の商品説明です。")
    expect(payload[:image_urls]).to include("https://takaratomymall.jp/images/item_1.jpg", "https://takaratomymall.jp/images/detail_extra.jpg")
    expect(payload[:normalized_payload]["brand"]).to eq("タカラトミー")
    expect(payload[:normalized_payload]["series"]).to eq("トミカ")
    expect(payload[:normalized_payload]["scale"]).to eq("1/64")
    expect(payload[:normalized_payload]["material"]).to eq("ダイキャスト")
    expect(payload[:normalized_payload]["barcode"]).to eq("4904810950783")
  end
end