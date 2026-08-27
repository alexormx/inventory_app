# frozen_string_literal: true

require 'rails_helper'

# Concurrencia real: la suite corre con transactional fixtures, que fijan UNA
# conexión para todos los hilos, así que `SELECT ... FOR UPDATE` nunca puede
# bloquearse contra sí mismo. Estos ejemplos se salen de ese modo para que cada
# hilo tenga su propia conexión y los locks de Postgres contiendan de verdad.
RSpec.describe 'Purchase order reduction under concurrency', type: :model do
  self.use_transactional_tests = false

  CLEAN_TABLES = %w[
    inventory_events
    inventories
    preorder_reservations
    sale_order_items
    sale_orders
    purchase_order_items
    purchase_orders
    products
    users
  ].freeze

  def truncate_all!
    ActiveRecord::Base.connection.execute(
      "TRUNCATE TABLE #{CLEAN_TABLES.join(', ')} RESTART IDENTITY CASCADE"
    )
  end

  before { truncate_all! }
  after  { truncate_all! }

  let!(:product) do
    create(:product, skip_seed_inventory: true, status: 'active',
                     preorder_available: true, backorder_allowed: false)
  end
  let!(:purchase_order) { create(:purchase_order, status: 'In Transit') }

  def line_with(quantity)
    create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: quantity)
  end

  def units_for(item)
    Inventory.where(purchase_order_item_id: item.id)
  end

  def run_in_parallel(count)
    barrier = Queue.new
    errors = Queue.new
    threads = count.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.pop
          begin
            yield i
          rescue StandardError => e
            errors << e
          end
        end
      end
    end
    sleep 0.05
    count.times { barrier << true }
    threads.each(&:join)
    collected = []
    collected << errors.pop until errors.empty?
    collected
  end

  it 'serializes two concurrent reductions of the same line without over-retiring' do
    item = line_with(6)
    expect(units_for(item).where(status: :in_transit).count).to eq(6)

    errors = run_in_parallel(2) do |i|
      target = i.zero? ? 4 : 3
      PurchaseOrderItem.find(item.id).update!(quantity: target)
    end

    expect(errors.select { |e| e.is_a?(ActiveRecord::Deadlocked) }).to be_empty

    live = units_for(item).where.not(status: :scrap)
    retired = units_for(item).where(status: :scrap)

    aggregate_failures do
      # El último escritor gana, y el inventario vivo queda exactamente en la
      # cantidad final: ése es el invariante, no el total de filas. Las piezas
      # retiradas persisten a propósito, y si el objetivo mayor se aplica al
      # final se crean unidades nuevas para alcanzarlo.
      expect(item.reload.quantity).to be >= 0
      expect([3, 4]).to include(item.quantity)
      expect(live.count).to eq(item.quantity)
      # Ninguna pieza retirada resucita ni queda comprometida.
      expect(retired.count).to be >= 2
      expect(retired.where.not(sale_order_id: nil).count).to eq(0)
      # Toda fila está viva o retirada, nunca destruida a medias.
      expect(live.count + retired.count).to eq(units_for(item).count)
    end
  end

  it 'never retires a unit that a concurrent checkout just committed' do
    item = line_with(4)

    errors = run_in_parallel(2) do |i|
      if i.zero?
        PurchaseOrderItem.find(item.id).update!(quantity: 2)
      else
        order = create(:sale_order)
        create(:sale_order_item,
               sale_order: order, product: product, quantity: 2,
               unit_cost: 40, unit_selling_price: 100, unit_final_price: 100,
               total_line_cost: 200)
      end
    end

    expect(errors.select { |e| e.is_a?(ActiveRecord::Deadlocked) }).to be_empty

    committed = Inventory.where(product_id: product.id).where.not(sale_order_id: nil)
    aggregate_failures do
      # Lo comprometido nunca queda retirado ni pierde su vínculo.
      expect(committed.where(status: :scrap).count).to eq(0)
      committed.each do |unit|
        expect(unit.sale_order_item_id).not_to be_nil
      end
      # Ninguna fila desapareció.
      expect(units_for(item).count).to eq(4)
    end
  end

  it 'never retires a unit that a concurrent preorder allocation just backed' do
    item = line_with(4)

    order = create(:sale_order)
    sale_line = create(:sale_order_item,
                       sale_order: order, product: product, quantity: 2, preorder_quantity: 2,
                       unit_cost: 40, unit_selling_price: 100, unit_final_price: 100,
                       total_line_cost: 200)
    create(:preorder_reservation,
           product: product, user: order.user, sale_order: order,
           sale_order_item: sale_line, quantity: 2, reserved_at: 2.days.ago)

    errors = run_in_parallel(2) do |i|
      if i.zero?
        PurchaseOrderItem.find(item.id).update!(quantity: 2)
      else
        Preorders::PreorderAllocator.new(product).call
      end
    end

    expect(errors.select { |e| e.is_a?(ActiveRecord::Deadlocked) }).to be_empty

    backed = Inventory.where(product_id: product.id, status: :pre_reserved)
    aggregate_failures do
      expect(Inventory.where(product_id: product.id, status: :scrap)
                      .where.not(sale_order_id: nil).count).to eq(0)
      expect(backed.pluck(:sale_order_item_id).compact.uniq).to eq([sale_line.id]) if backed.any?
      expect(units_for(item).count).to eq(4)
    end
  end

  it 'stays consistent when a reduction races the purchase order receipt' do
    item = line_with(4)

    errors = run_in_parallel(2) do |i|
      if i.zero?
        PurchaseOrderItem.find(item.id).update!(quantity: 2)
      else
        PurchaseOrder.find(purchase_order.id).update!(status: 'Delivered')
      end
    end

    expect(errors.select { |e| e.is_a?(ActiveRecord::Deadlocked) }).to be_empty

    aggregate_failures do
      expect(units_for(item).count).to eq(4)
      # Una pieza retirada no vuelve a circulación por recibir la orden.
      retired = units_for(item).where(status: :scrap)
      expect(retired.where.not(sale_order_id: nil).count).to eq(0)
      expect(Inventory.where(product_id: product.id).count).to eq(4)
    end
  end
end
