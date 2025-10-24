# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Checkout::CreateOrder, type: :service do
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }
  let(:product) { create(:product, selling_price: 50.0, skip_seed_inventory: true) }
  let(:address1) { create(:shipping_address, user: user1, default: true) }
  let(:address2) { create(:shipping_address, user: user2, default: true) }

  before do
    # Crear exactamente 1 unidad de inventario disponible
    Inventory.create!(
      product: product,
      status: :available,
      purchase_cost: 25.0
    )
    product.reload
  end

  it 'prevents oversell by revalidating inventory with pessimistic locking' do
    # Simular dos carritos que quieren comprar 1 unidad cada uno
    # Solo hay 1 unidad disponible, así que uno debe fallar

    cart1 = instance_double('Cart',
      empty?: false,
      items: [[product, 1]],
      total: 50.0
    )

    cart2 = instance_double('Cart',
      empty?: false,
      items: [[product, 1]],
      total: 50.0
    )

    result1 = nil
    result2 = nil

    t1 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        result1 = Checkout::CreateOrder.new(
          user: user1,
          cart: cart1,
          shipping_address_id: address1.id,
          shipping_method: 'standard',
          payment_method: 'efectivo',
          notes: 'Thread 1',
          idempotency_key: "t1-#{SecureRandom.hex(4)}"
        ).call
      end
    end

    # pequeña espera para aumentar probabilidad de colisión
    sleep 0.01

    t2 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        result2 = Checkout::CreateOrder.new(
          user: user2,
          cart: cart2,
          shipping_address_id: address2.id,
          shipping_method: 'standard',
          payment_method: 'efectivo',
          notes: 'Thread 2',
          idempotency_key: "t2-#{SecureRandom.hex(4)}"
        ).call
      end
    end

    t1.join
    t2.join

    # Uno de los resultados debe haber fallado debido a falta de stock
    successes = [result1, result2].count { |r| r&.success? }
    expect(successes).to eq(1), "Expected exactly 1 success but got #{successes}"

    # Verificar que solo se creó una orden
    expect(SaleOrder.count).to eq(1)
  end
end
