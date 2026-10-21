# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::ProductWriter do
  include ActionDispatch::TestProcess::FixtureFile

  let(:publish_error) { 'No se puede publicar: el producto no tiene existencias publicables, ni preventa ni backorder' }

  def photo(name = 'test1.png', type = 'image/png')
    fixture_file_upload(Rails.root.join('spec/fixtures/files', name), type)
  end

  def write(product: Product.new, attrs: {}, photos: [])
    described_class.new(product: product, attrs: attrs, photos: photos).call
  end

  def kataframe_attrs
    { product_name: 'Nissan Skyline', brand: 'Tomica', category: 'diecast', selling_price: '199' }
  end

  def existing(**attrs)
    create(:product, skip_seed_inventory: true, status: 'draft', **attrs)
  end

  describe 'creating' do
    it 'generates a KF SKU when none is given' do
      result = write(attrs: kataframe_attrs)
      expect(result).to be_success
      expect(result.product).to be_persisted
      expect(result.product.product_sku).to start_with('KF')
    end

    it 'generates distinct SKUs within the same second' do
      freeze_time do
        first = write(attrs: kataframe_attrs).product
        second = write(attrs: kataframe_attrs).product
        expect(first.product_sku).not_to eq(second.product_sku)
      end
    end

    it 'does not create anything when asked to publish an ineligible product' do
      expect do
        result = write(attrs: kataframe_attrs.merge(status: 'active'))
        expect(result).not_to be_success
        expect(result.errors).to eq([publish_error])
      end.not_to change(Product, :count)
    end
  end

  describe 'custom_attributes' do
    it 'merges into the existing attributes' do
      product = existing(custom_attributes: { 'series' => 'A', 'color' => 'rojo' })
      write(product: product, attrs: { custom_attributes: { 'color' => 'azul' } })
      expect(product.reload.custom_attributes).to eq('series' => 'A', 'color' => 'azul')
    end

    it 'removes a key sent blank' do
      product = existing(custom_attributes: { 'series' => 'A', 'color' => 'rojo' })
      write(product: product, attrs: { custom_attributes: { 'color' => '' } })
      expect(product.reload.custom_attributes).to eq('series' => 'A')
    end
  end

  describe 'photos' do
    it 'appends new photos at the end, in order, keeping the primary' do
      product = existing
      primary_before = product.primary_product_image.id

      result = write(product: product, photos: [photo('test2.png'), photo('test1.png')])

      expect(result).to be_success
      ordered = product.reload.ordered_product_images
      expect(ordered.size).to eq(4)
      expect(ordered.first.id).to eq(primary_before)
      expect(ordered.last(2).map { |a| a.filename.to_s }).to eq(%w[test2.png test1.png])
    end

    it 'makes the first photo the primary of a product without photos' do
      product = existing
      product.product_images.purge
      write(product: product.reload, photos: [photo])
      expect(product.reload.primary_product_image.filename.to_s).to eq('test1.png')
    end

    it 'rejects more than 10 photos and attaches none' do
      product = existing
      result = write(product: product, photos: Array.new(11) { photo })
      expect(result.errors).to eq(['Máximo 10 fotos por petición'])
      expect(product.reload.product_images.count).to eq(2)
    end

    it 'rejects a non-image file' do
      result = write(product: existing, photos: [photo('tkg_invoice_sample.csv', 'text/plain')])
      expect(result.errors).to eq(['La foto tkg_invoice_sample.csv no es JPG, PNG ni WebP'])
    end

    it 'rejects a photo over 15 MB' do
      big = photo
      allow(big).to receive(:size).and_return(15.megabytes + 1)
      result = write(product: existing, photos: [big])
      expect(result.errors).to eq(['La foto test1.png pesa más de 15 MB'])
    end
  end

  describe 'publishing' do
    it 'refuses to activate an ineligible product and persists nothing' do
      product = existing(product_name: 'Antes')
      result = write(product: product, attrs: { status: 'active', product_name: 'Después' })
      expect(result.errors).to eq([publish_error])
      expect(product.reload.status).to eq('draft')
      expect(product.product_name).to eq('Antes')
    end

    it 'activates an eligible product and clears auto_paused' do
      product = existing(preorder_available: true)
      product.update_columns(auto_paused: true)
      result = write(product: product, attrs: { status: 'active' })
      expect(result).to be_success
      expect(product.reload.status).to eq('active')
      expect(product.auto_paused).to be(false)
    end
  end
end
