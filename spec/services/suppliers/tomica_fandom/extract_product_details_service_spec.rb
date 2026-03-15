# frozen_string_literal: true

require "rails_helper"

RSpec.describe Suppliers::TomicaFandom::ExtractProductDetailsService do
  subject(:payload) { described_class.new(page_result).call }

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
          <p>The Lamborghini Temerario was released February 21, 2026. It replaced the <a title="No. 43 Honda NSX">No. 43 Honda NSX</a>. A blue first-edition variant was also released.</p>
          <h2><span class="mw-headline" id="Description">Description</span></h2>
          <p>The toy includes the main figure of the Lamborghini Temerario.</p>
          <p>It is a 1/64 model of the real-life vehicle.</p>
          <h2><span class="mw-headline" id="Trivia">Trivia</span></h2>
          <ul><li>The first Lamborghini Temerario in mainline Tomica.</li></ul>
        </div>
      HTML
    )
  end

  it "extracts overview, trivia, images and historical fields" do
    expect(payload[:title]).to eq("No. 43 Lamborghini Temerario")
    expect(payload[:image_urls].first).to include("43LamborghiniTemerarioBox.png")
    expect(payload[:normalized_payload]["scale"]).to eq("1/64")
    expect(payload[:normalized_payload]["release_text"]).to eq("February 21, 2026")
    expect(payload[:normalized_payload]["replaced"]).to eq("No. 43 Honda NSX")
    expect(payload[:normalized_payload]["trivia"]).to include("The first Lamborghini Temerario in mainline Tomica.")
  end
end