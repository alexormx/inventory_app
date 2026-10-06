# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Products::Enrichment::PhotoSourceService do
  let(:product) { create(:product, skip_seed_inventory: true).tap { |p| p.product_images.purge } }

  def png(color)
    Tempfile.create(['p', '.png']).tap { |f| system('convert', '-size', '20x20', "xc:#{color}", f.path, exception: true) }
  end

  it 'usa hasta 3 fotos del producto, la principal primero' do
    %w[red blue green yellow].each_with_index do |color, i|
      product.product_images.attach(io: File.open(png(color).path), filename: "p#{i}.png", content_type: 'image/png')
    end
    product.set_primary_product_image!(product.product_images.attachments.max_by(&:id).id)

    result = described_class.new(product.reload).call
    expect(result.jpegs.size).to eq(3)
    # El procesamiento es determinista: la primera foto enviada es la principal.
    expect(result.jpegs.first).to eq(Images::AiReadyJpeg.call(product.primary_product_image))
    expect(result.warnings).to be_empty
  end

  it 'sin fotos de producto usa las de sus piezas' do
    inventory = create(:inventory, product: product, item_condition: :loose)
    inventory.piece_images.attach(io: File.open(png('red').path), filename: 'pieza.png', content_type: 'image/png')
    expect(described_class.new(product.reload).call.jpegs.size).to eq(1)
  end

  it 'omite una foto ilegible y lo avisa' do
    product.product_images.attach(io: StringIO.new('no soy imagen'), filename: 'falsa.png', content_type: 'image/png')
    product.product_images.attach(io: File.open(png('red').path), filename: 'buena.png', content_type: 'image/png')
    result = described_class.new(product.reload).call
    expect(result.jpegs.size).to eq(1)
    expect(result.warnings.join).to include('falsa.png')
  end

  it 'sin fotos regresa vacío' do
    expect(described_class.new(product).call.jpegs).to eq([])
  end
end
