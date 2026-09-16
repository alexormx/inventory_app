# frozen_string_literal: true

require 'rails_helper'

# Canonical storefront availability. "Available now" is physical, located,
# unallocated inventory of a specific condition; in-transit stock is future
# availability and must never satisfy a normal storefront purchase.
RSpec.describe Inventories::Availability do
  let(:location) { create(:inventory_location) }
  # skip_seed_inventory: the product factory otherwise seeds 5 located
  # brand_new units, which would mask exactly what these specs assert.
  let(:product)  { create(:product, skip_seed_inventory: true) }

  def located_available(condition:, product: nil)
    create(
      :inventory,
      product: product || self.product,
      status: :available,
      item_condition: condition,
      inventory_location: location
    )
  end

  describe '.for' do
    it 'counts located available stock of the requested condition' do
      located_available(condition: :brand_new)
      located_available(condition: :brand_new)

      result = described_class.for(product, condition: 'brand_new')

      expect(result.available_now).to eq(2)
      expect(result).to be_available_now
    end

    it 'keeps conditions independent instead of aggregating by product' do
      located_available(condition: :brand_new)
      located_available(condition: :brand_new)
      located_available(condition: :mint)

      expect(described_class.for(product, condition: 'brand_new').available_now).to eq(2)
      expect(described_class.for(product, condition: 'mint').available_now).to eq(1)
      expect(described_class.for(product, condition: 'good').available_now).to eq(0)
    end

    it 'does not count in-transit stock as available now, and reports it separately' do
      create(:inventory, product: product, status: :in_transit, item_condition: :brand_new)

      result = described_class.for(product, condition: 'brand_new')

      expect(result.available_now).to eq(0)
      expect(result).not_to be_available_now
      expect(result.in_transit).to eq(1)
      expect(result).to be_in_transit
    end

    it 'does not count available stock that has no physical location' do
      create(:inventory, product: product, status: :available,
                         item_condition: :brand_new, inventory_location: nil)

      expect(described_class.for(product, condition: 'brand_new').available_now).to eq(0)
    end

    it 'does not count stock already allocated to a sale order' do
      inventory = located_available(condition: :brand_new)
      inventory.update!(status: :reserved, sale_order: create(:sale_order))

      expect(described_class.for(product, condition: 'brand_new').available_now).to eq(0)
    end

    it 'returns zero for a nil product without querying' do
      result = described_class.for(nil, condition: 'brand_new')

      expect(result.available_now).to eq(0)
      expect(result.in_transit).to eq(0)
    end
  end

  describe '.counts_for' do
    it 'returns available-now counts keyed by product and condition' do
      other = create(:product, skip_seed_inventory: true)
      located_available(condition: :brand_new)
      located_available(condition: :mint)
      located_available(condition: :mint, product: other)

      counts = described_class.counts_for([product.id, other.id])

      expect(counts[[product.id, 'brand_new']]).to eq(1)
      expect(counts[[product.id, 'mint']]).to eq(1)
      expect(counts[[other.id, 'mint']]).to eq(1)
      expect(counts[[other.id, 'brand_new']]).to be_nil
    end

    it 'excludes in-transit and unlocated stock' do
      create(:inventory, product: product, status: :in_transit, item_condition: :brand_new)
      create(:inventory, product: product, status: :available,
                         item_condition: :good, inventory_location: nil)

      expect(described_class.counts_for([product.id])).to eq({})
    end

    it 'returns an empty hash for no product ids' do
      expect(described_class.counts_for([])).to eq({})
    end
  end
end
