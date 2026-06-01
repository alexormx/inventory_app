require 'rails_helper'

RSpec.describe Products::ReconcilePublicationJob, type: :job do
  let(:location) { create(:inventory_location, :warehouse) }

  def active_product(**attrs)
    create(:product, skip_seed_inventory: true, status: :active,
                     preorder_available: false, backorder_allowed: false, **attrs)
  end

  it 'pausa un producto active sin stock publicable' do
    product = active_product

    described_class.new.perform

    product.reload
    expect(product.status).to eq('inactive')
    expect(product.auto_paused).to be(true)
  end

  it 'NO pausa si tiene una pieza available con ubicación' do
    product = active_product
    create(:inventory, product: product, status: :available,
                       inventory_location: location, item_condition: :brand_new)
    product.update_columns(status: 'active', auto_paused: false)

    described_class.new.perform

    expect(product.reload.status).to eq('active')
  end

  it 'NO pausa si tiene una pieza in_transit' do
    product = active_product
    create(:inventory, product: product, status: :in_transit, item_condition: :brand_new)
    product.update_columns(status: 'active', auto_paused: false)

    described_class.new.perform

    expect(product.reload.status).to eq('active')
  end

  it 'NO pausa si permite preventa o backorder' do
    preorder = active_product(preorder_available: true)
    backorder = active_product(backorder_allowed: true)

    described_class.new.perform

    expect(preorder.reload.status).to eq('active')
    expect(backorder.reload.status).to eq('active')
  end

  it 'NUNCA reactiva productos ya inactivos' do
    product = create(:product, skip_seed_inventory: true, status: :inactive,
                               auto_paused: true)
    create(:inventory, product: product, status: :available,
                       inventory_location: location, item_condition: :brand_new)

    described_class.new.perform

    expect(product.reload.status).to eq('inactive')
  end

  it 'pausa una pieza available SIN ubicación (no publicable)' do
    product = active_product
    create(:inventory, product: product, status: :available,
                       inventory_location: nil, item_condition: :brand_new)
    product.update_columns(status: 'active', auto_paused: false)

    described_class.new.perform

    expect(product.reload.status).to eq('inactive')
  end

  it 'devuelve el número de productos pausados' do
    active_product
    active_product

    expect(described_class.new.perform).to eq(2)
  end
end
