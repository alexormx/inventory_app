# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261101020000_backfill_shipments_for_store_orders.rb')

RSpec.describe BackfillShipmentsForStoreOrders do
  def store_order(status:, method: 'standard', name: 'Estándar')
    order = create(:sale_order, shipping_cost: 149)
    order.update_columns(status: status)
    create(:order_shipping_address, sale_order: order, shipping_method: method,
                                    raw_address_json: { 'shipping_method_name' => name })
    order
  end

  it 'creates the pending shipment of open store orders with the charged cost' do
    open_order = store_order(status: 'Confirmed')
    pickup = store_order(status: 'Pending', method: 'recoger_tienda', name: 'Recoger en Tienda')
    canceled = store_order(status: 'Canceled')
    total_before = open_order.reload.total_order_value

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    shipment = open_order.reload.shipment
    expect(shipment).to have_attributes(carrier: 'Estándar', shipping_cost: 149, status: 'pending')
    expect(open_order.total_order_value).to eq(total_before)
    expect(pickup.reload.shipment).to be_delivery_personal
    expect(canceled.reload.shipment).to be_nil
  end

  it 'leaves orders that already have a shipment alone' do
    order = store_order(status: 'Confirmed')
    create(:shipment, sale_order: order, carrier: 'DHL')

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    expect(Shipment.where(sale_order_id: order.id).pluck(:carrier)).to eq(['DHL'])
  end
end
