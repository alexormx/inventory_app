# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::CopyPhotosToProductJob do
  # La fábrica trae fotos de catálogo; aquí el producto nace sin fotos, como en quick_add.
  let(:product) { create(:product).tap { |p| p.product_images.purge } }
  let(:inventory) { create(:inventory, product: product, item_condition: :loose) }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def attach_piece(name, color)
    path = File.join(@dir, name)
    system('convert', '-size', '30x30', "xc:#{color}", '-set', 'comment', 'GPS 19.43,-99.13', path, exception: true)
    inventory.piece_images.attach(io: File.open(path), filename: name, content_type: 'image/png')
  end

  it 'copia las fotos de la pieza al producto, en orden y sin metadatos' do
    attach_piece('tres_cuartos.png', 'red')
    attach_piece('base.png', 'blue')
    described_class.perform_now(inventory.id)

    catalog = product.reload.product_images.attachments.sort_by(&:id)
    expect(catalog.map { |a| a.filename.to_s }).to eq(%w[tres_cuartos.png base.png])
    catalog.each do |attachment|
      attachment.blob.open { |file| expect(MiniMagick::Image.open(file.path)['%c'].to_s).not_to include('GPS') }
    end
  end

  it 'no duplica si corre dos veces' do
    attach_piece('tres_cuartos.png', 'red')
    2.times { described_class.perform_now(inventory.id) }
    expect(product.reload.product_images.attachments.size).to eq(1)
  end

  it 'omite un archivo que no es imagen en vez de publicarlo' do
    attach_piece('tres_cuartos.png', 'red')
    inventory.piece_images.attach(io: StringIO.new('no soy imagen'), filename: 'falsa.png', content_type: 'image/png')
    described_class.perform_now(inventory.id)

    expect(product.reload.product_images.attachments.map { |a| a.filename.to_s }).to eq(%w[tres_cuartos.png])
  end

  it 'no hace nada si la pieza ya no existe' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it 'al terminar de copiar encola el borrador de descripción, una sola vez' do
    attach_piece('tres_cuartos.png', 'red')
    expect do
      2.times { described_class.perform_now(inventory.id) }
    end.to have_enqueued_job(Products::Enrichment::GenerateDraftJob).exactly(:once)
  end
end
