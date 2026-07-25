# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'InventoryServices::ReserveSaleOrderItem' do
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:location) { create(:inventory_location) }
  let(:sale_order) { create(:sale_order) }

  def unallocated_line(condition: :brand_new, quantity: 1)
    create(
      :sale_order_item,
      sale_order: sale_order,
      product: product,
      item_condition: condition,
      quantity: quantity,
      unit_cost: 40,
      unit_selling_price: 100,
      unit_final_price: 100,
      total_line_cost: 100 * quantity
    )
  end

  it 'locks and assigns only inventory matching the sale-order line condition' do
    brand_new_line = unallocated_line(condition: :brand_new)
    mint_line = unallocated_line(condition: :mint)
    brand_new = create(:inventory, product: product, status: :available, item_condition: :brand_new, inventory_location: location)
    mint = create(:inventory, product: product, status: :available, item_condition: :mint, inventory_location: location)

    lock_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      lock_queries << payload[:sql] if payload[:sql].match?(/FOR UPDATE/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      InventoryServices::ReserveSaleOrderItem.call(brand_new_line)
      InventoryServices::ReserveSaleOrderItem.call(mint_line)
    end

    expect(brand_new.reload.sale_order_item_id).to eq(brand_new_line.id)
    expect(mint.reload.sale_order_item_id).to eq(mint_line.id)
    expect(brand_new.item_condition).to eq('brand_new')
    expect(mint.item_condition).to eq('mint')
    expect(lock_queries).not_to be_empty
  end

  it 'preserves the distinction between on-hand and in-transit reservations' do
    line = unallocated_line(quantity: 2)
    on_hand = create(:inventory, product: product, status: :available, inventory_location: location)
    incoming = create(:inventory, product: product, status: :in_transit)

    InventoryServices::ReserveSaleOrderItem.call(line)

    expect(on_hand.reload.status).to eq('reserved')
    expect(incoming.reload.status).to eq('pre_reserved')
    expect(on_hand.sold_price).to eq(100.to_d)
    expect(incoming.sold_price).to eq(100.to_d)
  end

  it 'does not load the shared product once per inventory callback' do
    line = unallocated_line(quantity: 2)
    create_list(:inventory, 2, product: product, status: :available, inventory_location: location)
    product_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      product_queries << sql if sql.match?(/SELECT "products"\.\* FROM "products"/) && payload[:name] != 'SCHEMA'
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      InventoryServices::ReserveSaleOrderItem.call(line)
    end

    expect(product_queries.size).to be <= 1, product_queries.join("\n")
  end

  it 'allows exactly one winner when two lines contend for one inventory row' do
    first_line = unallocated_line
    second_order = create(:sale_order)
    second_line = create(
      :sale_order_item,
      sale_order: second_order,
      product: product,
      quantity: 1,
      unit_cost: 40,
      unit_selling_price: 100,
      unit_final_price: 100,
      total_line_cost: 100
    )
    inventory = create(:inventory, product: product, status: :available, inventory_location: location)
    outcomes = Queue.new

    threads = [first_line, second_line].map do |line|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          InventoryServices::ReserveSaleOrderItem.call(line.reload)
          outcomes << :success
        rescue InventoryServices::ReserveSaleOrderItem::InsufficientInventory
          outcomes << :insufficient
        end
      end
    end
    threads.each(&:join)

    expect(2.times.map { outcomes.pop }).to contain_exactly(:success, :insufficient)
    expect(inventory.reload.sale_order_item_id).to be_in([first_line.id, second_line.id])
  end
end
