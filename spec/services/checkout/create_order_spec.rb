require 'rails_helper'

RSpec.describe Checkout::CreateOrder, type: :service do
  let(:user) { create(:user) }
  let!(:address) { create(:shipping_address, user: user) }
  let(:product) { create(:product, selling_price: 100, preorder_available: false, backorder_allowed: false) }

  # Carrito sencillo simulado; asumimos existe clase Cart que responde items y empty?
  class TestCart
    attr_reader :items
    def initialize(map) ; @items = map ; end
    def empty? ; @items.empty? ; end
    def total ; @items.sum { |p, q| p.selling_price * q } ; end
  end

  def build_cart(hash)
    TestCart.new(hash)
  end

  context 'happy path sin pendientes' do
    it 'crea sale_order, items, snapshot y payment' do
  allow(product).to receive(:current_on_hand).and_return(5)
      cart = build_cart({ product => 2 })

      result = described_class.new(
        user: user,
        cart: cart,
        shipping_address_id: address.id,
        shipping_method: 'standard',
        payment_method: 'transferencia_bancaria',
        notes: 'Probando',
        idempotency_key: nil
      ).call

      expect(result).to be_success
      so = result.sale_order
      expect(so).to be_present
      expect(so.sale_order_items.count).to eq(1)
      expect(OrderShippingAddress.where(sale_order: so).count).to eq(1)
      expect(so.payments.count).to eq(1)
      expect(so.total_order_value.to_f).to be > 0
    end
  end

  context 'stock insuficiente sin preorder/backorder' do
    it 'falla con error descriptivo' do
  allow(product).to receive(:current_on_hand).and_return(0)
      cart = build_cart({ product => 1 })
      result = described_class.new(
        user: user,
        cart: cart,
        shipping_address_id: address.id,
        shipping_method: 'standard',
        payment_method: 'transferencia_bancaria',
        notes: 'X',
        idempotency_key: nil
      ).call
      expect(result).not_to be_success
      expect(result.errors.first).to match(/no tiene suficiente stock/)
    end
  end
end
