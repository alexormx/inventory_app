require 'rails_helper'

RSpec.describe Cart, type: :model do
  let(:session) { {} }
  let(:cart) { described_class.new(session) }
  let(:product) { create(:product) }

  it 'adds a product' do
    cart.add_product(product.id)
    expect(cart.items.length).to eq(1)
  end

  it 'updates quantity' do
    cart.add_product(product.id)
    cart.update(product.id, 5)
    expect(cart.items.first.last).to eq(5)
  end

  it 'removes product' do
    cart.add_product(product.id)
    cart.remove(product.id)
    expect(cart.items).to be_empty
  end
end