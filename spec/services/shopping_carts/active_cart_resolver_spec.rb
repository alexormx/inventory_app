# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::ActiveCartResolver do
  let(:user) { create(:user) }

  describe '.find' do
    it 'returns nil when the user has no active cart' do
      expect(described_class.find(user)).to be_nil
    end

    it 'ignores terminal carts' do
      create(:shopping_cart, :cleared, user: user)
      expect(described_class.find(user)).to be_nil
    end

    it 'returns the active cart' do
      cart = create(:shopping_cart, user: user)
      expect(described_class.find(user)).to eq(cart)
    end
  end

  describe '.find_or_create!' do
    it 'creates exactly one active cart and then reuses it' do
      first = described_class.find_or_create!(user)
      second = described_class.find_or_create!(user)

      expect(first).to be_persisted
      expect(first.status).to eq('active')
      expect(second).to eq(first)
      expect(user.shopping_carts.count).to eq(1)
    end

    it 'does not create a cart for a different user' do
      described_class.find_or_create!(user)
      expect(create(:user).shopping_carts.count).to eq(0)
    end
  end

  describe '.create! losing the unique-index race' do
    it 're-fetches the winner and leaves the surrounding transaction usable' do
      winner = create(:shopping_cart, user: user)

      resolved = nil
      ActiveRecord::Base.transaction do
        resolved = described_class.create!(user)
        # The losing INSERT ran in a savepoint: the outer transaction is intact.
        expect(ShoppingCart.where(user: user).count).to eq(1)
      end

      expect(resolved).to eq(winner)
    end
  end
end
