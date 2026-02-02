require 'rails_helper'

RSpec.describe Checkout::CreateOrder, type: :service do
  let(:user) { create(:user) }
  let!(:address) { create(:shipping_address, user: user) }
  let(:product) { create(:product, selling_price: 100, preorder_available: false, backorder_allowed: false, status: :active) }

  # Carrito simulado con nuevo formato: items es array de hashes
  class TestCart
    attr_reader :items
    def initialize(items_array) ; @items = items_array ; end
    def empty? ; @items.empty? ; end
    def total ; @items.sum { |item| item[:price] * item[:quantity] } ; end
  end

  def build_cart(product, qty, condition: 'brand_new')
    items = [{
      product: product,
      condition: condition,
      quantity: qty,
      price: product.selling_price,
      collectible: condition != 'brand_new',
      label: condition == 'brand_new' ? 'Nuevo' : condition.upcase,
      line_total: product.selling_price * qty
    }]
    TestCart.new(items)
  end

  context 'happy path sin pendientes' do
    it 'crea sale_order, items, snapshot y payment' do
      allow(product).to receive(:current_on_hand).and_return(5)
      # Asegurar inventario físico disponible para evitar abortos en callbacks
      2.times do
        Inventory.create!(product: product, status: :available, purchase_cost: 10.0)
      end
      cart = build_cart(product, 2)

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
      expect(so.sale_order_items.first.item_condition).to eq('brand_new')
      expect(OrderShippingAddress.where(sale_order: so).count).to eq(1)
      expect(so.payments.count).to eq(1)
      expect(so.total_order_value.to_f).to be > 0
    end
  end

  context 'stock insuficiente sin preorder/backorder' do
    it 'falla con error descriptivo' do
      allow(product).to receive(:current_on_hand).and_return(0)
      cart = build_cart(product, 1)
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
