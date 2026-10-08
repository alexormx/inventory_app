# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Images::AiReadyJpeg do
  let(:product) { create(:product, skip_seed_inventory: true).tap { |p| p.product_images.purge } }

  def attach(io, filename)
    product.product_images.attach(io: io, filename: filename, content_type: 'image/jpeg')
    product.product_images.attachments.max_by(&:id)
  end

  it 'reduce a 1024 px, convierte a JPEG y quita metadatos' do
    Tempfile.create(['big', '.png']) do |big|
      system('convert', '-size', '3000x2000', 'xc:red', '-set', 'comment', 'GPS 19.43,-99.13', big.path, exception: true)
      image = MiniMagick::Image.read(described_class.call(attach(File.open(big.path), 'big.png')))
      expect([image.width, image.height].max).to be <= 1024
      expect(image.type).to eq('JPEG')
      expect(image['%c'].to_s).not_to include('GPS')
    end
  end

  it 'falla con InvalidImage si el archivo no es imagen' do
    attachment = attach(StringIO.new('no soy imagen'), 'falsa.jpg')
    expect { described_class.call(attachment) }.to raise_error(described_class::InvalidImage)
  end

  it 'pide a libjpeg decodificar ya reducido' do
    expect(ImageProcessing::MiniMagick::Processor).to receive(:load_image)
      .with(anything, hash_including(define: { jpeg: { size: '2048x2048' } }))
      .and_call_original
    Tempfile.create(['p', '.jpg']) do |f|
      system('convert', '-size', '40x30', 'xc:red', f.path, exception: true)
      described_class.call(attach(File.open(f.path), 'p.jpg'))
    end
  end
end
