# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::SessionHydrator do
  let(:cart) { create(:shopping_cart, :owned) }

  it 'returns an empty session cart for an empty persistent cart' do
    expect(described_class.call(cart)).to eq({})
  end

  it 'builds exactly the structure Cart.new(session) expects' do
    a = create(:product, skip_seed_inventory: true)
    b = create(:product, skip_seed_inventory: true)
    create(:shopping_cart_item, shopping_cart: cart, product: b, condition: 'misb', quantity: 1)
    create(:shopping_cart_item, shopping_cart: cart, product: a, condition: 'brand_new', quantity: 2)
    create(:shopping_cart_item, shopping_cart: cart, product: a, condition: 'loose', quantity: 1)

    session_cart = described_class.call(cart)

    expect(session_cart).to eq(
      a.id.to_s => { 'brand_new' => 2, 'loose' => 1 },
      b.id.to_s => { 'misb' => 1 }
    )
    expect(session_cart.keys).to all(be_a(String))
    expect(session_cart.values.flat_map(&:values)).to all(be_a(Integer))

    storefront = Cart.new({ cart: session_cart })
    expect(storefront.quantity_for(a.id, condition: 'brand_new')).to eq(2)
    expect(storefront.quantity_for(a.id, condition: 'loose')).to eq(1)
    expect(storefront.quantity_for(b.id, condition: 'misb')).to eq(1)
    expect(storefront.items.size).to eq(3)
  end

  it 'leaves out lines whose product no longer exists without touching them' do
    product = create(:product, skip_seed_inventory: true)
    ghost = create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 1)
    ghost.update_column(:product_id, nil) # what ON DELETE SET NULL does
    kept = create(:shopping_cart_item, shopping_cart: cart, quantity: 3)

    expect(described_class.call(cart)).to eq(kept.product_reference.to_s => { 'brand_new' => 3 })
    expect(cart.shopping_cart_items.count).to eq(2)
  end
end
