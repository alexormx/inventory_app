# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::TomicaFandom::BackfillItemService do
  let(:catalog_item) do
    create(:supplier_catalog_item,
           canonical_name: "No.43 Lamborghini Temerario",
           canonical_series: "Tomica",
           image_urls: ["https://www.hlj.com/productimages/tkt/tkt95078_0.jpg"])
  end
  let(:page_result) do
    Suppliers::TomicaFandom::FetchPageService::Result.new(
      page_title: "No. 43 Lamborghini Temerario",
      page_id: 37_605,
      display_title: "No. 43 Lamborghini Temerario",
      url: "https://tomica.fandom.com/wiki/No._43_Lamborghini_Temerario",
      images: ["43LamborghiniTemerarioBox.png"],
      html: <<~HTML
        <div class="mw-parser-output">
          <figure><a class="image" href="https://static.wikia.nocookie.net/tomica6057/images/9/96/43LamborghiniTemerarioBox.png/revision/latest"><img src="https://static.wikia.nocookie.net/tomica6057/images/9/96/43LamborghiniTemerarioBox.png/revision/latest/scale-to-width-down/300" /></a></figure>
          <h2><span class="mw-headline" id="Overview">Overview</span></h2>
          <p>The Lamborghini Temerario was released February 21, 2026. It replaced the <a title="No. 43 Honda NSX">No. 43 Honda NSX</a>.</p>
          <h2><span class="mw-headline" id="Description">Description</span></h2>
          <p>It is a 1/64 model of the real-life vehicle.</p>
          <h2><span class="mw-headline" id="Trivia">Trivia</span></h2>
          <ul><li>Mainline release for 2026.</li></ul>
        </div>
      HTML
    )
  end

  before do
    allow(Suppliers::TomicaFandom::ResolvePageService).to receive(:new).and_return(instance_double(Suppliers::TomicaFandom::ResolvePageService, call: page_result))
  end

  it "stores the fandom source and enriches the catalog item" do
    result = described_class.new(catalog_item).call

    expect(result.changed).to be true
    source = catalog_item.reload.source_for("tomica_fandom")
    expect(source).to be_present
    expect(source.fetch_status).to eq("ok")
    expect(source.metadata["page_title"]).to eq("No. 43 Lamborghini Temerario")
    expect(catalog_item.details_payload.dig("tomica_fandom", "scale")).to eq("1/64")
    expect(catalog_item.needs_review).to be true
  end
end