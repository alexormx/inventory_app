# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Checkout::CreateOrder, 'inventory revalidation' do
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }
  let(:product) { create(:product, selling_price: 100.0, skip_seed_inventory: true) }
  let(:address1) { create(:shipping_address, user: user1, default: true) }
  let(:address2) { create(:shipping_address, user: user2, default: true) }

  before do
    # Crear exactamente 2 unidades de inventario disponible
    2.times do
      Inventory.create!(
        product: product,
        status: :available,
        purchase_cost: 50.0,
        purchase_order_id: nil,
        sale_order_id: nil
      )
    end
    product.reload
  end

  describe 'pessimistic locking prevents overselling' do
    it 'prevents two concurrent checkouts from exceeding available inventory' do
      # Simular dos carritos que quieren comprar 2 unidades cada uno
      # Solo hay 2 unidades disponibles, así que uno debe fallar

      cart1 = mock_simple_cart(product, 2)
      cart2 = mock_simple_cart(product, 2)

      results = []
      threads = []

      # Lanzar dos threads que intentan crear órdenes simultáneamente
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          service = Checkout::CreateOrder.new(
            user: user1,
            cart: cart1,
            shipping_address_id: address1.id,
            shipping_method: 'standard',
            payment_method: 'transferencia_bancaria',
            notes: 'Order 1',
            idempotency_key: 'token-1'
          )
          results << service.call
        end
      end

      # Pequeña pausa para que el primer thread entre primero
      sleep 0.01

      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          service = Checkout::CreateOrder.new(
            user: user2,
            cart: cart2,
            shipping_address_id: address2.id,
            shipping_method: 'standard',
            payment_method: 'efectivo',
            notes: 'Order 2',
            idempotency_key: 'token-2'
          )
          results << service.call
        end
      end

      threads.each(&:join)

      # Exactamente uno debe haber tenido éxito y el otro debe haber fallado
      successes = results.count(&:success?)
      failures = results.count { |r| !r.success? }

      expect(successes).to eq(1), "Expected exactly 1 success, got #{successes}. Results: #{results.map { |r| {success: r.success?, errors: r.errors} }}"
      expect(failures).to eq(1), "Expected exactly 1 failure, got #{failures}"

      # El que falló debe tener mensaje de stock insuficiente
      failed_result = results.find { |r| !r.success? }
      expect(failed_result.errors.first).to match(/quedó sin stock suficiente/)

      # Verificar que solo se creó una orden
      expect(SaleOrder.count).to eq(1)

      # Verificar que las 2 unidades fueron reservadas por la orden exitosa
      successful_order = SaleOrder.last
      expect(successful_order.sale_order_items.sum(:quantity)).to eq(2)
    end
  end

  describe 'revalidation catches inventory changes between step3 and complete' do
    it 'fails if inventory becomes unavailable after user saw step3' do
      # Usuario ve step3 con 2 unidades disponibles
      cart = mock_simple_cart(product, 2)

      # Entre step3 y complete, alguien más compra las unidades
      # (simulamos marcando inventarios como sold)
      Inventory.where(product: product, status: :available).update_all(status: :sold)
      product.reload

      service = Checkout::CreateOrder.new(
        user: user1,
        cart: cart,
        shipping_address_id: address1.id,
        shipping_method: 'standard',
        payment_method: 'transferencia_bancaria',
        notes: 'Should fail',
        idempotency_key: 'token-fail'
      )

      result = service.call

      expect(result.success?).to be false
      expect(result.errors.first).to match(/no tiene suficiente stock|quedó sin stock suficiente/)
      expect(SaleOrder.count).to eq(0)
    end

    it 'succeeds if inventory is still available after revalidation' do
      cart = mock_simple_cart(product, 1)

      service = Checkout::CreateOrder.new(
        user: user1,
        cart: cart,
        shipping_address_id: address1.id,
        shipping_method: 'standard',
        payment_method: 'transferencia_bancaria',
        notes: 'Should succeed',
        idempotency_key: 'token-success'
      )

      result = service.call

      expect(result.success?).to be true
      expect(result.errors).to be_empty
      expect(SaleOrder.count).to eq(1)
    end
  end

  describe 'revalidation with preorder/backorder' do
    let(:preorder_product) { create(:product, selling_price: 50.0, preorder_available: true, skip_seed_inventory: true) }

    it 'allows creating order with preorder items even if immediate stock is 0' do
      # No hay inventario inmediato, pero permite preorder
      cart = mock_simple_cart(preorder_product, 3)

      service = Checkout::CreateOrder.new(
        user: user1,
        cart: cart,
        shipping_address_id: address1.id,
        shipping_method: 'standard',
        payment_method: 'efectivo',
        notes: 'Preorder test',
        idempotency_key: 'token-preorder'
      )

      result = service.call

      expect(result.success?).to be true
      expect(SaleOrder.count).to eq(1)

      order = SaleOrder.last
      item = order.sale_order_items.first
      expect(item.preorder_quantity).to eq(3)
    end
  end
end
