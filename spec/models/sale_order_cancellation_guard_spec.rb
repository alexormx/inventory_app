# frozen_string_literal: true

require 'rails_helper'

# La cancelación tiene un único camino canónico: SaleOrders::CancelOrderService.
# Estas pruebas fijan esa invariante a nivel de modelo para que ningún camino
# nuevo pueda cancelar una orden viva sin pasar por las validaciones del servicio.
RSpec.describe 'SaleOrder cancellation guard', type: :model do
  let(:customer) { create(:user) }
  let(:product) { create(:product, selling_price: 100.0, minimum_price: 10.0) }
  let(:order) do
    create(:sale_order, user: customer, status: 'Pending', subtotal: 100.0, total_order_value: 100.0)
  end

  describe 'direct status assignment on a persisted order' do
    it 'refuses a bare update to Canceled' do
      expect { order.update!(status: 'Canceled') }.to raise_error(ActiveRecord::RecordInvalid)
      expect(order.reload.status).to eq('Pending')
    end

    it 'refuses a bare update via the non-bang form and reports the dedicated flow' do
      expect(order.update(status: 'Canceled')).to be(false)
      expect(order.errors[:status].join).to match(/CancelOrderService|cancelaci/i)
      expect(order.reload.status).to eq('Pending')
    end

    it 'refuses the lowercase alias that normalize_status maps to Canceled' do
      expect { order.update!(status: 'cancelled') }.to raise_error(ActiveRecord::RecordInvalid)
      expect(order.reload.status).to eq('Pending')
    end

    it 'leaves linked inventory untouched when the guard rejects the change' do
      inventory = create(:inventory, product: product, status: :reserved,
                                     sale_order_id: order.id, sold_price: 100.0)

      expect { order.update!(status: 'Canceled') }.to raise_error(ActiveRecord::RecordInvalid)

      inventory.reload
      expect(inventory.status).to eq('reserved')
      expect(inventory.sale_order_id).to eq(order.id)
    end
  end

  describe 'transitions that are not cancellations' do
    it 'still allows ordinary status changes' do
      create(:payment, sale_order: order, amount: 100.0, status: 'Completed')

      expect { order.reload.update!(status: 'Confirmed') }.not_to raise_error
      expect(order.reload.status).to eq('Confirmed')
    end
  end

  describe 'historical import' do
    # Las órdenes canceladas heredadas se importan ya canceladas; un registro
    # nuevo todavía no puede tener inventario ni pagos que proteger.
    it 'allows creating a record that is already Canceled' do
      imported = build(:sale_order, user: customer, status: 'Canceled',
                                    subtotal: 0, total_order_value: 0)
      expect { imported.save! }.not_to raise_error
      expect(imported.reload.status).to eq('Canceled')
    end
  end

  describe 'the canonical service' do
    it 'is able to cancel through the guard' do
      expect { SaleOrders::CancelOrderService.new(order).call }.not_to raise_error
      expect(order.reload.status).to eq('Canceled')
    end

    it 'does not leave the authorization open on the instance afterwards' do
      SaleOrders::CancelOrderService.new(order).call
      expect(order.reload.status).to eq('Canceled')

      revived = create(:sale_order, user: customer, status: 'Pending',
                                    subtotal: 100.0, total_order_value: 100.0)
      expect { revived.update!(status: 'Canceled') }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
