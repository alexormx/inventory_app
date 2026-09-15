# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::ConvertCart do
  let(:user) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:sale_order) { create(:sale_order, user: user) }
  let!(:cart) { create(:shopping_cart, user: user) }
  let!(:line) { create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 2) }

  def convert(lines = [[product.id, 'brand_new', 2]])
    described_class.call(cart: cart, sale_order: sale_order, lines: lines)
  end

  it 'closes the cart as converted for the order' do
    convert

    cart.reload
    expect(cart.status).to eq('converted')
    expect(cart.sale_order_id).to eq(sale_order.id)
    expect(cart.converted_at).to be_present
    expect(cart.closed_at).to be_present
    expect(cart.anonymous_token_digest).to be_nil
    expect(cart.shopping_cart_items.count).to eq(1)
  end

  it 'refuses when the live lines no longer match the order snapshot' do
    line.update!(quantity: 3)

    expect { convert }.to raise_error(described_class::CartChanged, /changed/)
    expect(cart.reload.status).to eq('active')
  end

  it 'refuses a cart that is no longer active' do
    cart.update!(status: 'cleared', closed_at: Time.current)

    expect { convert }.to raise_error(described_class::CartChanged, /no longer active/)
  end

  it 'refuses a cart owned by another user' do
    stranger_order = create(:sale_order, user: create(:user))

    expect { described_class.call(cart: cart, sale_order: stranger_order, lines: [[product.id, 'brand_new', 2]]) }
      .to raise_error(described_class::CartChanged, /another user/)
    expect(cart.reload.status).to eq('active')
  end

  it 'ignores lines whose product was deleted, which the storefront never showed' do
    ghost = create(:shopping_cart_item, shopping_cart: cart, quantity: 1)
    ghost.update_column(:product_id, nil)

    expect { convert }.not_to raise_error
    expect(cart.reload.status).to eq('converted')
  end
end
