# frozen_string_literal: true

require 'rails_helper'

# El formulario genérico de edición permitía fijar status=Canceled y saltarse
# SaleOrders::CancelOrderService. Aunque el select ya no ofrece esa opción, la
# invariante debe sostenerse ante una petición manual.
RSpec.describe 'Admin::SaleOrders generic update cannot cancel', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }
  let(:product) { create(:product, selling_price: 100.0, minimum_price: 10.0) }
  let(:order) do
    create(:sale_order, user: customer, status: 'Pending', subtotal: 100.0, total_order_value: 100.0)
  end

  before { sign_in admin }

  def attempt_generic_cancel(target = order)
    patch admin_sale_order_path(target), params: { sale_order: { status: 'Canceled' } }
  end

  it 'does not cancel the order and points the admin at the dedicated action' do
    attempt_generic_cancel

    expect(order.reload.status).to eq('Pending')
    expect(flash[:alert]).to be_present
  end

  context 'with sold inventory' do
    let!(:inventory) do
      create(:inventory, product: product, status: :sold, sale_order_id: order.id, sold_price: 100.0)
    end

    it 'is blocked and leaves the sold inventory linked and untouched' do
      order.update_column(:status, 'Confirmed')

      attempt_generic_cancel

      expect(order.reload.status).to eq('Confirmed')
      inventory.reload
      expect(inventory.status).to eq('sold')
      expect(inventory.sale_order_id).to eq(order.id)
      expect(inventory.sold_price).to eq(100.0)
    end
  end

  context 'with pre_sold inventory' do
    let!(:inventory) do
      create(:inventory, product: product, status: :pre_sold, sale_order_id: order.id, sold_price: 100.0)
    end

    it 'is blocked and leaves the pre_sold inventory linked and untouched' do
      order.update_column(:status, 'Confirmed')

      attempt_generic_cancel

      expect(order.reload.status).to eq('Confirmed')
      inventory.reload
      expect(inventory.status).to eq('pre_sold')
      expect(inventory.sale_order_id).to eq(order.id)
    end
  end

  context 'with a completed payment' do
    let!(:payment) { create(:payment, sale_order: order, amount: 100.0, status: 'Completed') }

    it 'is blocked and leaves the payment untouched' do
      # Un pago que cubre el total promueve la orden a Confirmed al crearse.
      status_before = order.reload.status

      attempt_generic_cancel

      expect(order.reload.status).to eq(status_before)
      expect(order.status).not_to eq('Canceled')
      expect(payment.reload.status).to eq('Completed')
      expect(payment.amount).to eq(100.0)
    end
  end

  context 'with a shipped shipment' do
    it 'is blocked and preserves the shipment' do
      create(:payment, sale_order: order, amount: 100.0, status: 'Completed')
      order.update_column(:status, 'In Transit')
      shipment = create(:shipment, sale_order: order)
      shipment.update_column(:status, Shipment.statuses[:shipped])

      attempt_generic_cancel

      expect(order.reload.status).to eq('In Transit')
      expect(shipment.reload.status).to eq('shipped')
    end
  end

  context 'with a delivered shipment' do
    # Reproduce el estado histórico SO-202009-013 (Canceled + shipment delivered).
    it 'is blocked so the historical Canceled+Delivered state cannot recur' do
      create(:payment, sale_order: order, amount: 100.0, status: 'Completed')
      order.update_column(:status, 'Delivered')
      shipment = create(:shipment, sale_order: order)
      shipment.update_column(:status, Shipment.statuses[:delivered])

      attempt_generic_cancel

      expect(order.reload.status).to eq('Delivered')
      expect(shipment.reload.status).to eq('delivered')
    end
  end

  it 'still allows ordinary status edits through the generic form' do
    create(:payment, sale_order: order, amount: 100.0, status: 'Completed')

    patch admin_sale_order_path(order), params: { sale_order: { status: 'Confirmed' } }

    expect(order.reload.status).to eq('Confirmed')
  end

  it 'keeps the dedicated cancel action working for a safe order' do
    post cancel_admin_sale_order_path(order)

    expect(order.reload.status).to eq('Canceled')
  end

  it 'does not offer Canceled as an ordinary status option in the edit form' do
    get edit_admin_sale_order_path(order)

    expect(response.body).to include('value="Confirmed"')
    expect(response.body).not_to include('value="Canceled"')
  end
end
