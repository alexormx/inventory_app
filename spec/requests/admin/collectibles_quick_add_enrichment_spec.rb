# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin quick_add liga la identificación con IA', type: :request do
  include ActiveJob::TestHelper

  RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job

  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  def lookup_for(user, status: :done)
    Collectibles::AiLookup.new(user: user).tap do |l|
      l.photos.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
      l.save!
      l.update!(status: status, result: { 'identification' => { 'brand' => 'Tomica' } })
    end
  end

  def quick_add(extra = {})
    post admin_collectibles_quick_add_path, params: {
      use_existing_product: '0',
      product: { product_name: 'Pieza IA', category: 'Autos a escala', brand: 'Tomica', selling_price: '250' },
      inventory: { item_condition: 'loose' }
    }.merge(extra)
  end

  it 'liga la búsqueda terminada del mismo admin al producto nuevo' do
    lookup = lookup_for(admin)
    quick_add(ai_lookup_id: lookup.id)
    expect(lookup.reload.product).to eq(Product.order(:id).last)
  end

  it 'ignora la búsqueda de otro admin' do
    lookup = lookup_for(create(:user, :admin))
    quick_add(ai_lookup_id: lookup.id)
    expect(lookup.reload.product).to be_nil
  end

  it 'ignora una búsqueda que no terminó' do
    lookup = lookup_for(admin, status: :running)
    quick_add(ai_lookup_id: lookup.id)
    expect(lookup.reload.product).to be_nil
  end

  it 'no liga nada a un producto existente' do
    lookup = lookup_for(admin)
    product = create(:product)
    post admin_collectibles_quick_add_path, params: {
      use_existing_product: '1', existing_product_id: product.id, ai_lookup_id: lookup.id,
      inventory: { item_condition: 'loose' }
    }
    expect(lookup.reload.product).to be_nil
  end

  describe 'borrador automático de descripción' do
    it 'un producto nuevo sin fotos recibe su borrador en cola de inmediato' do
      expect { quick_add }.to have_enqueued_job(Products::Enrichment::GenerateDraftJob)
      expect(Product.order(:id).last.description_drafts.queued.count).to eq(1)
    end

    it 'con vista 3/4 el borrador espera a la copia de fotos' do
      photo = Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/test1.png'), 'image/png')
      expect { quick_add(inventory: { item_condition: 'loose', three_quarter_image: photo }) }
        .to have_enqueued_job(Collectibles::CopyPhotosToProductJob)
        .and(not_have_enqueued_job(Products::Enrichment::GenerateDraftJob))
    end

    it 'un producto existente no recibe borrador' do
      product = create(:product)
      expect do
        post admin_collectibles_quick_add_path, params: { use_existing_product: '1', existing_product_id: product.id,
                                                          inventory: { item_condition: 'loose' } }
      end.not_to have_enqueued_job(Products::Enrichment::GenerateDraftJob)
    end
  end
end
