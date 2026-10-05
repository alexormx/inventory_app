# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin quick_add guarda las fotos', type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def upload(name, color)
    path = File.join(@dir, name)
    system('convert', '-size', '30x30', "xc:#{color}", path, exception: true)
    Rack::Test::UploadedFile.new(path, 'image/png')
  end

  def quick_add(product_params, images)
    post admin_collectibles_quick_add_path, params: {
      inventory: { item_condition: 'loose', piece_images: images }
    }.merge(product_params)
  end

  def new_product_params
    { use_existing_product: '0', product: { product_name: 'Pieza de prueba IA', category: 'Autos a escala', brand: 'Tomica', selling_price: '250' } }
  end

  it 'un producto nuevo recibe las mismas fotos, en el mismo orden, como fotos propias' do
    # Un recuadro vacío llega como "" y se ignora.
    quick_add(new_product_params, [upload('tres_cuartos.png', 'red'), '', upload('base.png', 'blue'), upload('extra.png', 'green')])

    inventory = Inventory.order(:id).last
    product = inventory.product
    piece = inventory.piece_images.attachments.sort_by(&:id)
    catalog = product.product_images.attachments.sort_by(&:id)

    expect(piece.map { |a| a.filename.to_s }).to eq(%w[tres_cuartos.png base.png extra.png])
    expect(catalog.map { |a| a.filename.to_s }).to eq(%w[tres_cuartos.png base.png extra.png])
    expect(product.primary_product_image.filename.to_s).to eq('tres_cuartos.png')
    # Copias independientes: borrar la foto de la pieza no borra la del producto.
    expect(catalog.map(&:blob_id) & piece.map(&:blob_id)).to be_empty
    expect(catalog.map { |a| a.blob.checksum }).to eq(piece.map { |a| a.blob.checksum })
  end

  it 'borrar la foto de la pieza deja intacta la del producto' do
    quick_add(new_product_params, [upload('tres_cuartos.png', 'red')])
    inventory = Inventory.order(:id).last

    inventory.piece_images.attachments.first.purge
    expect(inventory.product.reload.product_images.attachments.size).to eq(1)
    expect(inventory.product.product_images.attachments.first.blob.service.exist?(inventory.product.product_images.attachments.first.blob.key)).to be(true)
  end

  it 'con un producto existente no toca sus fotos de catálogo' do
    product = create(:product)
    expect do
      quick_add({ use_existing_product: '1', existing_product_id: product.id }, [upload('tres_cuartos.png', 'red')])
    end.not_to(change { product.reload.product_images.attachments.count })

    expect(Inventory.order(:id).last.piece_images.attachments.size).to eq(1)
  end

  it 'sin fotos no adjunta nada' do
    quick_add(new_product_params, [''])
    inventory = Inventory.order(:id).last
    expect(inventory.piece_images).not_to be_attached
    expect(inventory.product.product_images).not_to be_attached
  end
end
