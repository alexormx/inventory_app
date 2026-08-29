# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin inbound receiving and physical location assignment', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:product) do
    create(
      :product,
      skip_seed_inventory: true,
      status: 'active',
      preorder_available: true,
      backorder_allowed: false,
      product_name: 'Inbound Skyline',
      product_sku: 'INBOUND-SKY-10'
    )
  end
  let(:warehouse) { create(:inventory_location, :warehouse) }
  let!(:location_a) { create(:inventory_location, :shelf, parent: warehouse, name: 'Shelf A') }
  let!(:location_b) { create(:inventory_location, :shelf, parent: warehouse, name: 'Shelf B') }

  def create_preorder_demand(quantity:)
    order = create(:sale_order)
    line = create(
      :sale_order_item,
      sale_order: order,
      product: product,
      quantity: quantity,
      preorder_quantity: quantity,
      unit_cost: 40,
      unit_selling_price: 100,
      unit_final_price: 100,
      total_line_cost: 100 * quantity
    )
    reservation = create(
      :preorder_reservation,
      product: product,
      user: order.user,
      sale_order: order,
      sale_order_item: line,
      quantity: quantity,
      reserved_at: 2.days.ago
    )
    [order, line, reservation]
  end

  def select_location(location)
    post admin_location_assignment_batch_location_path, params: { location_id: location.id }
  end

  def assign(quantity, turbo: false)
    post admin_location_assignment_batch_lines_path,
         params: { product_id: product.id, quantity: quantity, q: product.product_sku }
    headers = turbo ? { 'Accept' => 'text/vnd.turbo-stream.html' } : {}
    post admin_location_assignment_batch_assign_all_path,
         params: { q: product.product_sku }, headers: headers
  end

  before { sign_in admin }

  it 'preserves commitments from known inbound supply through receipt and FIFO location assignment' do
    sale_order, sale_order_item, reservation = create_preorder_demand(quantity: 3)
    purchase_order = create(:purchase_order, status: 'Pending')
    purchase_order_item = create(
      :purchase_order_item,
      purchase_order: purchase_order,
      product: product,
      quantity: 10
    )

    inbound = Inventory.where(purchase_order_item: purchase_order_item).order(:created_at, :id).to_a
    committed_ids = inbound.first(3).map(&:id)

    aggregate_failures 'known inbound supply' do
      expect(inbound.size).to eq(10)
      expect(Inventory.where(id: committed_ids, status: :pre_reserved).count).to eq(3)
      expect(Inventory.where(purchase_order_item: purchase_order_item, status: :in_transit).count).to eq(7)
      expect(Inventory.where(purchase_order_item: purchase_order_item).where.not(inventory_location_id: nil)).to be_empty
      expect(reservation.reload).to be_assigned
    end

    purchase_order.update!(status: 'In Transit')
    patch confirm_receipt_admin_purchase_order_path(purchase_order)

    aggregate_failures 'received but unlocated' do
      expect(purchase_order.reload.status).to eq('Delivered')
      expect(Inventory.where(id: committed_ids, status: :reserved).count).to eq(3)
      expect(Inventory.where(purchase_order_item: purchase_order_item, status: :available).count).to eq(7)
      expect(Inventory.where(purchase_order_item: purchase_order_item).where.not(inventory_location_id: nil)).to be_empty
      expect(Inventory.customer_sellable.where(product: product)).to be_empty
    end

    get admin_inventory_unlocated_path, params: { q: product.product_sku }

    aggregate_failures 'operator-facing unlocated breakdown' do
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-assignable="10"')
      expect(response.body).to include('data-available="7"')
      expect(response.body).to include('data-reserved="3"')
    end

    purchase_stats = product.reload.attributes.slice(
      'total_purchase_quantity', 'total_purchase_value', 'average_purchase_cost', 'total_purchase_order'
    )

    select_location(location_a)
    expect { assign(5, turbo: true) }.to change {
      InventoryEvent.where(event_type: 'physical_inventory_verification').count
    }.by(5)

    aggregate_failures 'first physical assignment' do
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('target="location-current-inventory"')
      expect(response.body).to include('target="location-batch-panel"')
      expect(response.body).to include('target="product-search-results"')
      expect(response.body).to include('target="unlocated-overview-totals"')
      expect(response.body).to include('data-total-assignable="5"')
      expect(response.body).to include('data-available="5"')
      expect(response.body).to include('data-reserved="0"')
      expect(inbound.first(5).map { |row| row.reload.inventory_location_id }).to all(eq(location_a.id))
      expect(inbound.drop(5).map { |row| row.reload.inventory_location_id }).to all(be_nil)
      expect(Inventory.customer_sellable.where(product: product).count).to eq(2)
      expect(Inventory.where(product: product, inventory_location_id: nil).count).to eq(5)
      expect(Inventory.where(id: committed_ids).pluck(:status).uniq).to eq(['reserved'])
      expect(Inventory.where(id: committed_ids).pluck(:sale_order_id).uniq).to eq([sale_order.id])
      expect(Inventory.where(id: committed_ids).pluck(:sale_order_item_id).uniq).to eq([sale_order_item.id])
      expect(product.reload.attributes.slice(*purchase_stats.keys)).to eq(purchase_stats)
    end

    select_location(location_b)
    expect { assign(5, turbo: true) }.to change {
      InventoryEvent.where(event_type: 'physical_inventory_verification').count
    }.by(5)

    events = InventoryEvent.where(event_type: 'physical_inventory_verification')
                           .where(inventory_id: inbound.map(&:id))
    aggregate_failures 'final physical assignment' do
      expect(Inventory.where(product: product, inventory_location_id: nil)).to be_empty
      expect(response.body).to include('data-total-assignable="0"')
      expect(Inventory.where(product: product, inventory_location: location_a).count).to eq(5)
      expect(Inventory.where(product: product, inventory_location: location_b).count).to eq(5)
      expect(Inventory.customer_sellable.where(product: product).count).to eq(7)
      expect(events.count).to eq(10)
      expect(events.map { |event| event.metadata['assignment_batch_id'] }.uniq.size).to eq(2)
      expect(Inventory.where(id: committed_ids).pluck(:status).uniq).to eq(['reserved'])
      expect(Inventory.where(id: committed_ids).pluck(:sale_order_id).uniq).to eq([sale_order.id])
      expect(Inventory.where(id: committed_ids).pluck(:sale_order_item_id).uniq).to eq([sale_order_item.id])
      expect(product.reload.attributes.slice(*purchase_stats.keys)).to eq(purchase_stats)
    end
  end
end
