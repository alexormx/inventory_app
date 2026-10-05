# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin quick_add guarda las fotos', type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  # La foto lleva un comentario con "GPS" como metadato de prueba: -strip lo quita.
  def upload(name, color)
    path = File.join(@dir, name)
    system('convert', '-size', '30x30', "xc:#{color}", '-set', 'comment', 'GPS 19.43,-99.13', path, exception: true)
    Rack::Test::UploadedFile.new(path, 'image/png')
  end

  def quick_add(product_params, three_quarter: nil, others: [])
    post admin_collectibles_quick_add_path, params: {
      inventory: { item_condition: 'loose', three_quarter_image: three_quarter || '', piece_images: others }
    }.merge(product_params)
  end

  def new_product_params
    { use_existing_product: '0',
      product: { product_name: 'Pieza de prueba IA', category: 'Autos a escala', brand: 'Tomica', selling_price: '250' } }
  end

  def filenames(attached)
    attached.attachments.sort_by(&:id).map { |a| a.filename.to_s }
  end

  it 'con vista 3/4, el producto nuevo recibe copias sin metadatos, en el mismo orden' do
    perform_enqueued_jobs do
      # Un recuadro vacío llega como "" y se ignora.
      quick_add(new_product_params, three_quarter: upload('tres_cuartos.png', 'red'),
                                    others: ['', upload('base.png', 'blue'), upload('extra.png', 'green')])
    end

    inventory = Inventory.order(:id).last
    product = inventory.product.reload
    expect(filenames(inventory.piece_images)).to eq(%w[tres_cuartos.png base.png extra.png])
    expect(filenames(product.product_images)).to eq(%w[tres_cuartos.png base.png extra.png])
    expect(product.primary_product_image.filename.to_s).to eq('tres_cuartos.png')

    catalog = product.product_images.attachments
    expect(catalog.map(&:blob_id) & inventory.piece_images.attachments.map(&:blob_id)).to be_empty
    catalog.each do |attachment|
      attachment.blob.open { |file| expect(MiniMagick::Image.open(file.path)['%c'].to_s).not_to include('GPS') }
    end
  end

  it 'copia las fotos al producto en segundo plano, después del alta' do
    expect do
      quick_add(new_product_params, three_quarter: upload('tres_cuartos.png', 'red'))
    end.to have_enqueued_job(Collectibles::CopyPhotosToProductJob).with(kind_of(Integer))

    expect(enqueued_jobs.find { |j| j[:job] == Collectibles::CopyPhotosToProductJob }[:args]).to eq([Inventory.order(:id).last.id])
    expect(Inventory.order(:id).last.product.product_images).not_to be_attached
  end

  it 'sin vista 3/4 las fotos quedan sólo en la pieza' do
    expect do
      quick_add(new_product_params, others: [upload('base.png', 'blue')])
    end.not_to have_enqueued_job(Collectibles::CopyPhotosToProductJob)

    inventory = Inventory.order(:id).last
    expect(filenames(inventory.piece_images)).to eq(%w[base.png])
    expect(inventory.product.product_images).not_to be_attached
  end

  it 'con un producto existente no toca sus fotos de catálogo' do
    product = create(:product)
    catalog_before = product.product_images.attachments.map(&:id)
    expect do
      quick_add({ use_existing_product: '1', existing_product_id: product.id }, three_quarter: upload('tres_cuartos.png', 'red'))
    end.not_to have_enqueued_job(Collectibles::CopyPhotosToProductJob)

    expect(Inventory.order(:id).last.piece_images.attachments.size).to eq(1)
    expect(product.reload.product_images.attachments.map(&:id)).to eq(catalog_before)
  end

  it 'sin fotos no adjunta nada' do
    quick_add(new_product_params, others: [''])
    inventory = Inventory.order(:id).last
    expect(inventory.piece_images).not_to be_attached
    expect(inventory.product.product_images).not_to be_attached
  end
end
