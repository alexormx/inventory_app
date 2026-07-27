# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Checkout::CreateOrder, 'P0 invariants', type: :service do
  let(:user) { create(:user) }
  let(:address) { create(:shipping_address, user: user) }
  let(:location) { create(:inventory_location) }
  let(:product) do
    create(
      :product,
      skip_seed_inventory: true,
      selling_price: 100.00,
      average_purchase_cost: 40.00,
      preorder_available: false,
      backorder_allowed: false
    )
  end
  let(:cart) do
    Cart.new(
      cart: {
        product.id.to_s => { 'brand_new' => 1 }
      }
    )
  end

  before do
    SiteSetting.delete_all
    SiteSetting.set('tax_enabled', true, 'boolean')
    SiteSetting.set('tax_rate_percent', '16.00', 'string')
    create(
      :shipping_method,
      code: 'envio_estandar',
      name: 'Envío estándar confirmado',
      base_cost: 99.00,
      active: true
    )
  end

  def call_service(**overrides)
    described_class.new(
      user: user,
      cart: cart,
      shipping_address_id: address.id,
      shipping_method: 'envio_estandar',
      payment_method: 'transferencia_bancaria',
      notes: '',
      idempotency_key: SecureRandom.urlsafe_base64(16),
      **overrides
    ).call
  end

  it 'persists the same server total in the order and initial payment' do
    inventory = create(:inventory, product: product, purchase_cost: 40.00, status: :available, inventory_location: location)

    order = call_service.sale_order.reload
    line = order.sale_order_items.first

    expect(order.subtotal).to eq(100.to_d)
    expect(order.tax_rate).to eq(16.to_d)
    expect(order.total_tax).to eq(16.to_d)
    expect(order.shipping_cost).to eq(99.to_d)
    expect(order.total_order_value).to eq(215.to_d)
    expect(order.payments.sole.amount).to eq(215.to_d)
    expect(line.unit_cost).to eq(40.to_d)
    expect(line.unit_selling_price).to eq(100.to_d)
    expect(line.unit_final_price).to eq(100.to_d)
    expect(line.total_line_cost).to eq(100.to_d)
    expect(inventory.reload.sold_price).to eq(100.to_d)
    expect(order.order_shipping_address.shipping_method_name).to eq('Envío estándar confirmado')
  end

  it 'does not change a persisted order when the current IVA setting changes' do
    create(:inventory, product: product, purchase_cost: 40.00, status: :available, inventory_location: location)
    order = call_service.sale_order.reload

    SiteSetting.set('tax_rate_percent', '8.00', 'string')
    order.recalculate_totals!(persist: true)

    expect(order.reload.tax_rate).to eq(16.to_d)
    expect(order.total_tax).to eq(16.to_d)
    expect(order.total_order_value).to eq(215.to_d)
    expect(order.payments.sole.amount).to eq(215.to_d)
  end

  it 'rolls back the order and reservation when the initial Payment cannot persist' do
    inventory = create(:inventory, product: product, status: :available, inventory_location: location)
    allow_any_instance_of(Payment).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

    expect { call_service }.to raise_error(ActiveRecord::RecordInvalid)

    expect(SaleOrder.where(user: user)).to be_empty
    expect(Payment.all).to be_empty
    expect(inventory.reload.status).to eq('available')
    expect(inventory.sale_order_id).to be_nil
    expect(inventory.sale_order_item_id).to be_nil
  end

  it 'does not swallow a reservation failure in production' do
    inventory = create(:inventory, product: product, status: :available, inventory_location: location)
    allow(Rails.env).to receive(:production?).and_return(true)
    allow_any_instance_of(Inventory).to receive(:update!).and_raise(StandardError, 'reservation failed')

    expect { call_service }.to raise_error(StandardError, 'reservation failed')

    expect(SaleOrder.where(user: user)).to be_empty
    expect(Payment.all).to be_empty
    expect(inventory.reload.status).to eq('available')
  end

  it 'links a preorder reservation to its original order and line' do
    product.update!(preorder_available: true)

    order = call_service.sale_order.reload
    line = order.sale_order_items.sole
    reservation = PreorderReservation.sole

    expect(line.preorder_quantity).to eq(1)
    expect(reservation.sale_order).to eq(order)
    expect(reservation.sale_order_item).to eq(line)
  end

  it 'reserves in-transit inventory as pre-reserved for the original line' do
    inventory = create(:inventory, product: product, status: :in_transit)

    line = call_service.sale_order.sale_order_items.sole

    expect(inventory.reload.status).to eq('pre_reserved')
    expect(inventory.sale_order_item_id).to eq(line.id)
  end

  it 'does not disable Bullet while creating the order' do
    create(:inventory, product: product, status: :available, inventory_location: location)
    allow(Bullet).to receive(:enabled?).and_return(true)

    expect(Bullet).not_to receive(:enable=)

    expect(call_service).to be_success
  end
end
