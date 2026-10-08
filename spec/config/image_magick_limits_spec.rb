# frozen_string_literal: true

require "rails_helper"

# Los dynos tienen 512 MB: sin topes, ImageMagick decodifica una foto de 12 MP
# en ~137 MB por proceso (memoria + map). Con estos, ~43 MB.
RSpec.describe "Topes de memoria de ImageMagick" do
  it "los fija al arrancar la app" do
    expect(ENV.fetch("MAGICK_MEMORY_LIMIT")).to eq("64MiB")
    expect(ENV.fetch("MAGICK_MAP_LIMIT")).to eq("128MiB")
  end

  it "los procesos de ImageMagick que lanza la app los respetan" do
    resources = `identify -list resource`
    expect(resources).to match(/Memory:\s+64MiB/)
    expect(resources).to match(/Map:\s+128MiB/)
  end
end
