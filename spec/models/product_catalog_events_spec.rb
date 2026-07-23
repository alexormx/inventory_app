# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Product, type: :model do
  describe 'publication event stamping' do
    it 'stamps first_published_at on first activation' do
      product = create(:product, status: 'draft', skip_seed_inventory: true)
      expect(product.first_published_at).to be_nil

      freeze_time do
        product.update!(status: 'active')
        expect(product.first_published_at).to be_within(1.second).of(Time.current)
      end
      expect(product.republished_at).to be_nil
    end

    it 'stamps republished_at on later activations and preserves first_published_at' do
      product = create(:product, status: 'draft', skip_seed_inventory: true)
      product.update!(status: 'active')
      first = product.first_published_at
      expect(first).to be_present

      product.update!(status: 'inactive')
      expect(product.republished_at).to be_nil

      freeze_time do
        product.update!(status: 'active')
        expect(product.republished_at).to be_within(1.second).of(Time.current)
      end
      expect(product.reload.first_published_at).to be_within(1.second).of(first)
    end

    it 'does not stamp when a non-status attribute changes' do
      product = create(:product, status: 'active', skip_seed_inventory: true)
      product.update_columns(republished_at: nil, first_published_at: nil)

      product.update!(product_name: 'Renombrado')

      expect(product.reload.first_published_at).to be_nil
      expect(product.republished_at).to be_nil
    end

    it 'does not stamp when auto-paused via update_columns' do
      product = create(:product, status: 'active', skip_seed_inventory: true)
      product.update_columns(republished_at: nil)

      product.auto_pause_if_unpublishable!

      expect(product.reload.status).to eq('inactive')
      expect(product.republished_at).to be_nil
    end
  end

  describe '#mark_restock_from_receipt!' do
    it 'sets first_stocked_at on the initial stocking without marking a restock' do
      product = create(:product, status: 'active', skip_seed_inventory: true)
      product.update_columns(first_stocked_at: nil, restocked_at: nil)

      freeze_time do
        product.mark_restock_from_receipt!(was_zero: true)
        expect(product.first_stocked_at).to be_within(1.second).of(Time.current)
      end
      expect(product.restocked_at).to be_nil
    end

    it 'sets restocked_at when re-stocked after the initial load' do
      product = create(:product, status: 'active', skip_seed_inventory: true)
      product.update_columns(first_stocked_at: 60.days.ago, restocked_at: nil)

      freeze_time do
        product.mark_restock_from_receipt!(was_zero: true)
        expect(product.restocked_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'ignores partial restocks (prior stock was positive)' do
      product = create(:product, status: 'active', skip_seed_inventory: true)
      product.update_columns(first_stocked_at: 60.days.ago, restocked_at: nil)

      product.mark_restock_from_receipt!(was_zero: false)

      expect(product.reload.restocked_at).to be_nil
    end
  end
end
