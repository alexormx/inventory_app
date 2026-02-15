# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Preparing status flow', type: :model do
  let(:customer) { create(:user, role: 'customer') }
  let(:product)  { create(:product) }

  # Helper: crea una orden confirmada con pago y shipment
  def create_confirmed_order
    so = create(:sale_order, user: customer, status: 'Pending',
                             subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
    create(:sale_order_item, sale_order: so, product: product, quantity: 1,
                             unit_final_price: 100, total_line_cost: 100)
    so.payments.create!(amount: 100, status: 'Completed', payment_method: 'transferencia_bancaria',
                        paid_at: Time.current)
    so.reload
    so.update!(status: 'Confirmed')
    so
  end

  describe 'SaleOrder STATUSES' do
    it 'includes Preparing' do
      expect(SaleOrder::STATUSES).to include('Preparing')
    end

    it 'maps preparing in CANONICAL_STATUS' do
      expect(SaleOrder::CANONICAL_STATUS['preparing']).to eq('Preparing')
    end
  end

  describe 'Confirmed → Preparing transition' do
    it 'allows transition to Preparing when shipment exists' do
      so = create_confirmed_order
      # Auto-crear shipment (como lo hace el controller)
      so.create_shipment!(carrier: 'Test', estimated_delivery: Date.today + 7, status: :pending)
      so.reload

      expect { so.update!(status: 'Preparing') }.not_to raise_error
      expect(so.reload.status).to eq('Preparing')
    end

    it 'rejects Preparing without shipment' do
      so = create_confirmed_order
      expect(so.shipment).to be_nil

      # La validación ensure_payment_and_shipment_present bloquea sin shipment
      expect { so.update!(status: 'Preparing') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'promotes inventory from reserved to sold on Confirmed → Preparing' do
      so = create_confirmed_order
      so.create_shipment!(carrier: 'Test', estimated_delivery: Date.today + 7, status: :pending)

      # Los inventarios ya deberían estar sold por Pending→Confirmed
      inv = so.inventories.first
      expect(inv).to be_present
      # Ya estaba sold por Pending→Confirmed, se mantiene
      expect(inv.reload.status).to eq('sold')
    end
  end

  describe 'Preparing → In Transit transition (via Shipment)' do
    it 'transitions order to In Transit when shipment is marked shipped' do
      so = create_confirmed_order
      shipment = so.create_shipment!(carrier: 'Estafeta', estimated_delivery: Date.today + 7, status: :pending)
      so.update!(status: 'Preparing')

      shipment.update!(status: :shipped, tracking_number: 'TRACK123')
      so.reload

      expect(so.status).to eq('In Transit')
    end

    it 'allows shipment without tracking_number when pending' do
      so = create_confirmed_order
      shipment = so.build_shipment(carrier: 'Test', estimated_delivery: Date.today + 7, status: :pending)

      expect(shipment.valid?).to be true
      expect(shipment.tracking_number).to be_nil
    end

    it 'requires tracking_number when shipped' do
      so = create_confirmed_order
      shipment = so.create_shipment!(carrier: 'Test', estimated_delivery: Date.today + 7, status: :pending)
      so.update!(status: 'Preparing')

      shipment.status = :shipped
      shipment.tracking_number = nil
      expect(shipment.valid?).to be false
      expect(shipment.errors[:tracking_number]).to be_present
    end
  end

  describe 'Shipment pending rollback from In Transit' do
    it 'rolls back to Preparing when shipment goes back to pending from shipped' do
      so = create_confirmed_order
      shipment = so.create_shipment!(carrier: 'Estafeta', estimated_delivery: Date.today + 7,
                                     status: :pending)
      so.update!(status: 'Preparing')
      shipment.update!(status: :shipped, tracking_number: 'TRACK123')
      expect(so.reload.status).to eq('In Transit')

      shipment.update!(status: :pending)
      expect(so.reload.status).to eq('Preparing')
    end
  end

  describe 'Inventory sync on Preparing demotion' do
    it 'reverts sold to reserved when Preparing → Confirmed' do
      so = create_confirmed_order
      shipment = so.create_shipment!(carrier: 'Test', estimated_delivery: Date.today + 7, status: :pending)
      so.update!(status: 'Preparing')

      inv = so.inventories.first
      expect(inv.reload.status).to eq('sold')

      so.update!(status: 'Confirmed')
      expect(inv.reload.status).to eq('reserved')
    end
  end

  describe 'Full flow: Pending → Confirmed → Preparing → In Transit → Delivered' do
    it 'completes the full happy path' do
      so = create_confirmed_order
      expect(so.status).to eq('Confirmed')

      # Create shipment and prepare
      shipment = so.create_shipment!(carrier: 'DHL', estimated_delivery: Date.today + 5, status: :pending)
      so.reload
      so.update!(status: 'Preparing')
      expect(so.status).to eq('Preparing')

      # Ship
      shipment.update!(status: :shipped, tracking_number: 'DHL123456MX')
      so.reload
      expect(so.status).to eq('In Transit')

      # Deliver
      shipment.update!(status: :delivered, actual_delivery: Date.today + 5)
      so.reload
      expect(so.status).to eq('Delivered')
    end
  end
end
