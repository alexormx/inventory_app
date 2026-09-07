# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCartItem, type: :model do
  describe 'quantity' do
    it 'is invalid without a positive quantity' do
      item = build(:shopping_cart_item, quantity: 0)

      expect(item).not_to be_valid
      expect(item.errors[:quantity]).to be_present
    end

    it 'rejects a non-positive quantity at the database level too' do
      item = build(:shopping_cart_item, quantity: -1)

      expect { item.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /shopping_cart_items_quantity_positive/)
    end

    it 'is valid with a positive integer quantity' do
      item = build(:shopping_cart_item, quantity: 3)

      expect(item).to be_valid
    end
  end

  describe 'condition' do
    it 'accepts every canonical Inventory::ITEM_CONDITIONS value' do
      Inventory::ITEM_CONDITIONS.each_key do |condition|
        item = build(:shopping_cart_item, condition: condition.to_s)

        expect(item).to be_valid, "expected #{condition} to be valid"
      end
    end

    it 'rejects a condition outside the canonical allowlist' do
      expect { build(:shopping_cart_item, condition: 'not_a_real_condition') }
        .to raise_error(ArgumentError)
    end
  end

  describe 'product_reference uniqueness' do
    it 'rejects a duplicate product_reference + condition within the same cart' do
      cart = create(:shopping_cart, :owned)
      product = create(:product)
      create(:shopping_cart_item, shopping_cart: cart, product: product, condition: 'brand_new')
      duplicate = build(:shopping_cart_item, shopping_cart: cart, product: product, condition: 'brand_new')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:product_reference]).to be_present
    end

    it 'enforces the same uniqueness at the database level' do
      cart = create(:shopping_cart, :owned)
      product = create(:product)
      create(:shopping_cart_item, shopping_cart: cart, product: product, condition: 'brand_new')
      duplicate = build(:shopping_cart_item, shopping_cart: cart, product: product, condition: 'brand_new')

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same product with a different condition in the same cart' do
      cart = create(:shopping_cart, :owned)
      product = create(:product)
      create(:shopping_cart_item, shopping_cart: cart, product: product, condition: 'brand_new')
      other_condition = build(:shopping_cart_item, shopping_cart: cart, product: product, condition: 'loose')

      expect(other_condition).to be_valid
    end

    it 'allows the same product and condition in a different cart' do
      product = create(:product)
      create(:shopping_cart_item, shopping_cart: create(:shopping_cart, :owned), product: product,
                                   condition: 'brand_new')
      other_cart_item = build(:shopping_cart_item, shopping_cart: create(:shopping_cart, :anonymous),
                                                     product: product, condition: 'brand_new')

      expect(other_cart_item).to be_valid
    end
  end

  describe 'product deletion' do
    it 'nullifies product_id while retaining product_reference and product_name_snapshot' do
      product = create(:product, product_name: 'Doomed Product', skip_seed_inventory: true)
      item = create(:shopping_cart_item, product: product, product_reference: product.id,
                                          product_name_snapshot: product.product_name)

      product.destroy!
      item.reload

      expect(item.product_id).to be_nil
      expect(item.product_reference).to eq(product.id)
      expect(item.product_name_snapshot).to eq('Doomed Product')
    end
  end

  describe 'cart deletion' do
    it 'destroys its items when the owning cart is destroyed' do
      cart = create(:shopping_cart, :owned)
      item = create(:shopping_cart_item, shopping_cart: cart)

      cart.destroy!

      expect(ShoppingCartItem.exists?(item.id)).to be false
    end
  end
end
