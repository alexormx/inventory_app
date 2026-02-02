require 'rails_helper'

RSpec.describe Cart, type: :model do
  let(:session) { {} }
  let(:cart) { described_class.new(session) }
  let(:product) { create(:product) }

  describe 'basic operations' do
    it 'adds a product with default brand_new condition' do
      cart.add_product(product.id)
      expect(cart.items.length).to eq(1)
      expect(cart.items.first[:condition]).to eq('brand_new')
      expect(cart.items.first[:quantity]).to eq(1)
    end

    it 'adds a product with specific condition' do
      cart.add_product(product.id, 1, condition: 'misb')
      expect(cart.items.first[:condition]).to eq('misb')
    end

    it 'updates quantity' do
      cart.add_product(product.id)
      cart.update(product.id, 5, condition: 'brand_new')
      expect(cart.items.first[:quantity]).to eq(5)
    end

    it 'removes product by condition' do
      cart.add_product(product.id, 1, condition: 'brand_new')
      cart.add_product(product.id, 1, condition: 'misb')
      cart.remove(product.id, condition: 'brand_new')
      expect(cart.items.length).to eq(1)
      expect(cart.items.first[:condition]).to eq('misb')
    end

    it 'removes all conditions when no condition specified' do
      cart.add_product(product.id, 1, condition: 'brand_new')
      cart.add_product(product.id, 1, condition: 'misb')
      cart.remove(product.id)
      expect(cart.items).to be_empty
    end
  end

  describe 'limits' do
    it 'allows up to 3 brand_new items' do
      expect(cart.can_add?(product.id, condition: 'brand_new', quantity: 1)).to be true
      cart.add_product(product.id, 3, condition: 'brand_new')
      expect(cart.can_add?(product.id, condition: 'brand_new', quantity: 1)).to be false
    end

    it 'allows only 1 collectible per condition' do
      expect(cart.can_add?(product.id, condition: 'misb', quantity: 1)).to be true
      cart.add_product(product.id, 1, condition: 'misb')
      expect(cart.can_add?(product.id, condition: 'misb', quantity: 1)).to be false
    end
  end

  describe 'totals' do
    it 'calculates total correctly with mixed conditions' do
      # Brand new uses product.selling_price
      cart.add_product(product.id, 2, condition: 'brand_new')
      expected_total = product.selling_price * 2
      expect(cart.total).to eq(expected_total)
    end

    it 'returns item_count correctly' do
      cart.add_product(product.id, 2, condition: 'brand_new')
      cart.add_product(product.id, 1, condition: 'misb')
      expect(cart.item_count).to eq(3)
    end
  end

  describe 'legacy migration' do
    it 'migrates legacy format to new format' do
      # Simular formato legacy: {product_id => quantity}
      session[:cart] = { product.id.to_s => 3 }
      migrated_cart = described_class.new(session)

      expect(migrated_cart.items.length).to eq(1)
      expect(migrated_cart.items.first[:condition]).to eq('brand_new')
      expect(migrated_cart.items.first[:quantity]).to eq(3)
    end
  end
end