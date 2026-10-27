# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin manual sale orders queue their shortage as preorders', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:location) { create(:inventory_location) }

  before { sign_in admin }

  def create_order(quantity)
    post admin_sale_orders_path, params: {
      sale_order: {
        user_id: customer.id, order_date: Time.zone.today, status: 'Pending',
        subtotal: 100 * quantity, tax_rate: 0, total_tax: 0, total_order_value: 100 * quantity,
        sale_order_items_attributes: {
          '0' => { product_id: product.id, quantity: quantity, unit_cost: 40,
                   unit_final_price: 100, total_line_cost: 100 * quantity }
        }
      }
    }
    SaleOrder.order(:created_at).last
  end

  def located_stock(quantity)
    rows = create_list(:inventory, quantity, product: product, status: :damaged)
    Inventory.where(id: rows).update_all(status: Inventory.statuses[:available], inventory_location_id: location.id)
    rows
  end

  it 'reserves what is on hand and puts the exact shortage in the preorder queue' do
    located_stock(1)

    order = create_order(3)
    line = order.sale_order_items.sole

    aggregate_failures do
      expect(line.inventory_units.where(status: :reserved).count).to eq(1)
      expect(line.preorder_quantity).to eq(2)
      expect(PreorderReservation.fifo_pending.where(sale_order_item: line).sum(:quantity)).to eq(2)
      expect(PreorderReservation.where(sale_order_item: line).sole.user).to eq(customer)
      expect(order.reload.notes.to_s).not_to include('🛑')
    end
  end

  it 'takes received stock that has no location yet' do
    create(:inventory, product: product, status: :available, inventory_location: nil)

    order = create_order(1)
    line = order.sale_order_items.sole

    aggregate_failures do
      expect(line.inventory_units.where(status: :reserved, inventory_location_id: nil).count).to eq(1)
      expect(line.preorder_quantity).to eq(0)
      expect(PreorderReservation.where(sale_order_item: line).sole).to be_assigned
    end
  end

  it 'queues only the new shortage when the line quantity grows' do
    order = create_order(1)
    line = order.sale_order_items.sole

    patch admin_sale_order_path(order), params: {
      sale_order: { sale_order_items_attributes: { '0' => { id: line.id, quantity: 3, total_line_cost: 300 } } }
    }

    aggregate_failures do
      expect(line.reload.preorder_quantity).to eq(3)
      expect(PreorderReservation.pending.where(sale_order_item: line).sum(:quantity)).to eq(3)
    end
  end

  it 'assigns the waiting line as soon as the purchase arrives, before it is located' do
    order = create_order(2)
    line = order.sale_order_items.sole
    purchase_order = create(:purchase_order, status: 'In Transit')
    create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: 2)

    expect(line.reload.inventory_units.where(status: :pre_reserved).count).to eq(2)

    patch confirm_receipt_admin_purchase_order_path(purchase_order)

    aggregate_failures do
      expect(line.reload.inventory_units.where(status: :reserved, inventory_location_id: nil).count).to eq(2)
      expect(line.preorder_quantity).to eq(0)
      expect(PreorderReservation.pending.where(sale_order_item: line)).to be_empty
    end
  end
end
