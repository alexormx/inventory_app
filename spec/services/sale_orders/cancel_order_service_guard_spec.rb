# frozen_string_literal: true

require 'rails_helper'

# El guard de SaleOrder deja a SaleOrders::CancelOrderService como único camino
# vivo hacia 'Canceled'. Estas pruebas cubren el lado seguro de esa invariante:
# el servicio sigue liberando lo que debe liberar y sigue rechazando lo que no
# puede tocar sin una devolución controlada.
RSpec.describe SaleOrders::CancelOrderService, type: :service do
  let(:customer) { create(:user) }
  let(:product) { create(:product, selling_price: 100.0, minimum_price: 10.0) }
  let(:order) do
    create(:sale_order, user: customer, status: 'Pending', subtotal: 100.0, total_order_value: 100.0)
  end

  describe 'safe releases' do
    it 'releases reserved inventory back to available and clears sold_price' do
      inventory = create(:inventory, product: product, status: :reserved,
                                     sale_order_id: order.id, sold_price: 100.0)

      described_class.new(order).call

      expect(order.reload.status).to eq('Canceled')
      inventory.reload
      expect(inventory.status).to eq('available')
      expect(inventory.sale_order_id).to be_nil
      expect(inventory.sale_order_item_id).to be_nil
      expect(inventory.sold_price).to be_nil
    end

    it 'returns pre_reserved inventory to in_transit and clears sold_price' do
      inventory = create(:inventory, product: product, status: :pre_reserved,
                                     sale_order_id: order.id, sold_price: 100.0)

      described_class.new(order).call

      expect(order.reload.status).to eq('Canceled')
      inventory.reload
      expect(inventory.status).to eq('in_transit')
      expect(inventory.sale_order_id).to be_nil
      expect(inventory.sold_price).to be_nil
    end

    it 'cancels the preorder reservations linked to the order' do
      reservation = create(:preorder_reservation, product: product, user: customer,
                                                  sale_order_id: order.id, status: :pending)

      described_class.new(order).call

      expect(order.reload.status).to eq('Canceled')
      expect(reservation.reload.status).to eq('cancelled')
      expect(reservation.cancelled_at).to be_present
    end
  end

  describe 'blocked cancellations leave no partial mutation' do
    it 'refuses an order holding sold inventory and touches nothing' do
      inventory = create(:inventory, product: product, status: :sold,
                                     sale_order_id: order.id, sold_price: 100.0)

      expect { described_class.new(order).call }
        .to raise_error(described_class::CancellationBlocked)

      expect(order.reload.status).to eq('Pending')
      inventory.reload
      expect(inventory.status).to eq('sold')
      expect(inventory.sale_order_id).to eq(order.id)
      expect(inventory.sold_price).to eq(100.0)
    end

    it 'refuses an order with a received payment and leaves its inventory intact' do
      inventory = create(:inventory, product: product, status: :reserved,
                                     sale_order_id: order.id, sold_price: 100.0)
      # Un pago que cubre el total promueve la orden a Confirmed, y esa promoción
      # convierte la pieza reservada en vendida. Lo que se fija aquí es que el
      # intento de cancelar no altere nada de eso.
      create(:payment, sale_order: order, amount: 100.0, status: 'Completed')
      status_before = order.reload.status
      inventory_status_before = inventory.reload.status

      expect { described_class.new(order.reload).call }
        .to raise_error(described_class::CancellationBlocked)

      expect(order.reload.status).to eq(status_before)
      expect(order.status).not_to eq('Canceled')
      inventory.reload
      expect(inventory.status).to eq(inventory_status_before)
      expect(inventory.sale_order_id).to eq(order.id)
      expect(inventory.sold_price).to eq(100.0)
    end

    it 'refuses an order that already shipped and leaves its preorder untouched' do
      reservation = create(:preorder_reservation, product: product, user: customer,
                                                  sale_order_id: order.id, status: :pending)
      order.update_column(:status, 'In Transit')

      expect { described_class.new(order.reload).call }
        .to raise_error(described_class::CancellationBlocked)

      expect(order.reload.status).to eq('In Transit')
      expect(reservation.reload.status).to eq('pending')
    end
  end

  describe 'idempotency' do
    it 'is a no-op on an order that is already canceled' do
      described_class.new(order).call
      expect(order.reload.status).to eq('Canceled')

      expect { described_class.new(order.reload).call }.not_to raise_error
      expect(order.reload.status).to eq('Canceled')
    end
  end
end
