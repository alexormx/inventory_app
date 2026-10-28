# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Favorite, type: :model do
  let(:user) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  describe '.save_for' do
    it 'opens one favorite per customer and product' do
      described_class.save_for(user, product)
      described_class.save_for(user, product)

      expect(described_class.open.where(user: user, product: product).count).to eq(1)
    end

    it 'keeps the original source when the product was already saved' do
      described_class.save_for(user, product, source: 'heart')
      described_class.save_for(user, product, source: 'abandoned_cart')

      expect(described_class.open.sole.source).to eq('heart')
    end

    it 'opens a new favorite after the customer removed the previous one' do
      described_class.save_for(user, product).remove!

      described_class.save_for(user, product)

      expect(described_class.where(user: user, product: product).count).to eq(2)
      expect(described_class.open.count).to eq(1)
    end
  end

  describe '#remove!' do
    it 'closes the favorite instead of deleting it' do
      favorite = described_class.save_for(user, product)

      favorite.remove!

      expect(favorite.reload.removed_at).to be_present
      expect(favorite.removal_reason).to eq('removed')
      expect(described_class.open).to be_empty
    end
  end

  describe 'when the customer buys the product' do
    it 'leaves the list marked as purchased with the order' do
      favorite = described_class.save_for(user, product)
      order = create(:sale_order, user: user)

      create(:sale_order_item, sale_order: order, product: product)

      expect(favorite.reload.removal_reason).to eq('purchased')
      expect(favorite.sale_order_id).to eq(order.id)
      expect(described_class.open).to be_empty
    end

    it 'does not touch the favorites of other customers' do
      other = described_class.save_for(create(:user), product)

      create(:sale_order_item, sale_order: create(:sale_order, user: user), product: product)

      expect(other.reload.removed_at).to be_nil
    end
  end
end
