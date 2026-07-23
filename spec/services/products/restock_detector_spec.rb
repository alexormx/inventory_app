# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Products::RestockDetector do
  def available_product
    product = create(:product, status: 'active', skip_seed_inventory: true)
    product.update_columns(first_stocked_at: nil, restocked_at: nil)
    product
  end

  it 'stamps first_stocked_at (no restock) on a 0 -> positive first stocking' do
    product = available_product
    create(:inventory, product: product, status: :available)

    described_class.call([product.id], prev_available_counts: {})

    product.reload
    expect(product.first_stocked_at).to be_present
    expect(product.restocked_at).to be_nil
  end

  it 'stamps restocked_at on a 0 -> positive transition after the initial load' do
    product = available_product
    product.update_columns(first_stocked_at: 90.days.ago)
    create(:inventory, product: product, status: :available)

    described_class.call([product.id], prev_available_counts: { product.id => 0 })

    expect(product.reload.restocked_at).to be_present
  end

  it 'ignores partial restocks where prior available count was positive' do
    product = available_product
    product.update_columns(first_stocked_at: 90.days.ago)
    create(:inventory, product: product, status: :available)

    described_class.call([product.id], prev_available_counts: { product.id => 3 })

    expect(product.reload.restocked_at).to be_nil
  end

  it 'does nothing when the product has no available stock after receipt' do
    product = available_product

    described_class.call([product.id], prev_available_counts: {})

    product.reload
    expect(product.first_stocked_at).to be_nil
    expect(product.restocked_at).to be_nil
  end
end
