# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::Hlj::ExtractProductDetailsService do
  subject(:payload) { described_class.new(document, source_url: source_url).call }

  let(:source_url) { "https://www.hlj.com/no-43-lamborghini-temerario-tkt95078" }
  let(:document) do
    Nokogiri::HTML(<<~HTML)
      <html>
        <head>
          <meta property="og:title" content="No.43 Lamborghini Temerario">
          <meta property="og:image" content="//www.hlj.com/productimages/tkt/tkt95078_0.jpg">
        </head>
        <body>
          <h1>No.43 Lamborghini Temerario</h1>
          <div class="product-stock">In Stock</div>
          <p class="price">$74.29 MXN</p>
          <button>Add To Cart</button>
          <h3>Description</h3>
          <p>This is a completed toy designed for children and/or collectors.</p>
          <div class="fotorama">
            <a href="https://www.hlj.com/productimages/tkt/tkt95078_0.jpg">img</a>
            <a href="https://www.hlj.com/productimages/tkt/tkt95078_1.jpg">img</a>
          </div>
          <div class="product-details">
            <ul>
              <li>Code: TKT95078</li>
              <li>JAN Code: 4904810950783</li>
              <li>Release Date: 2026/02/21</li>
              <li>Category: Cars &amp; Bikes</li>
              <li>Country of Origin: Japan</li>
              <li>Cancellation Deadline: 2025-12-05</li>
              <li>Series: Tomica</li>
              <li>Item Type: Toys</li>
              <li>Manufacturer: Takara Tomy</li>
              <li>Item Size/Weight: 8.2 x 4 x 3 cm / 50g</li>
            </ul>
          </div>
        </body>
      </html>
    HTML
  end

  it "extracts normalized product details" do
    expect(payload[:name]).to eq("No.43 Lamborghini Temerario")
    expect(payload[:raw_status]).to eq("In Stock")
    expect(payload[:canonical_brand]).to eq("Takara Tomy")
    expect(payload[:barcode]).to eq("4904810950783")
    expect(payload[:supplier_product_code]).to eq("TKT95078")
    expect(payload[:canonical_release_date]).to eq(Date.new(2026, 2, 21))
    expect(payload[:canonical_price]).to eq(74.29.to_d)
    expect(payload[:image_urls].size).to eq(2)
    expect(payload[:image_urls].first).to start_with("https://")
    expect(payload[:normalized_payload]["stock_status_normalized"]).to eq("in_stock")
    expect(payload[:normalized_payload]["item_size"]).to eq("8.2 x 4 x 3 cm")
    expect(payload[:normalized_payload]["weight"]).to eq("50g")
  end

  it "ignores warehouse warning text as a product title" do
    warning_doc = Nokogiri::HTML(<<~HTML)
      <html>
        <head>
          <meta property="og:title" content="Kirby Play Wit Waddle Dee 3D Pouch">
        </head>
        <body>
          <h1>After click "Buy Now", the item are placed in PRIVATE WAREHOUSE.</h1>
          <p class="price">$13.48 MXN</p>
        </body>
      </html>
    HTML

    payload = described_class.new(warning_doc, source_url: source_url).call

    expect(payload[:name]).to eq("Kirby Play Wit Waddle Dee 3D Pouch")
  end
end