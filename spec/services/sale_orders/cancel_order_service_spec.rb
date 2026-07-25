# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SaleOrders::CancelOrderService, type: :service do
  let(:user) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:other_product) { create(:product, skip_seed_inventory: true) }
  let(:sale_order) do
    create(
      :sale_order,
      user: user,
      status: 'Pending',
      subtotal: 100,
      total_order_value: 100
    )
  end

  def create_line(order: sale_order, line_product: product, **attributes)
    create(
      :sale_order_item,
      sale_order: order,
      product: line_product,
      quantity: 1,
      unit_final_price: 100,
      total_line_cost: 100,
      **attributes
    )
  end

  def create_linked_inventory(status:, order: sale_order, line: nil, inventory_product: product)
    create(
      :inventory,
      product: inventory_product,
      status: status,
      sale_order: order,
      sale_order_item: line
    )
  end

  describe '#call' do
    it 'cancels a pending unpaid in-stock order and releases only its reservation' do
      line = create_line
      inventory = create_linked_inventory(status: :reserved, line: line)
      payment = create(:payment, sale_order: sale_order, amount: 100, status: 'Pending')

      result = described_class.new(sale_order).call

      expect(result.status).to eq('Canceled')
      expect(inventory.reload).to have_attributes(
        status: 'available',
        sale_order_id: nil,
        sale_order_item_id: nil,
        sold_price: nil
      )
      expect(payment.reload.status).to eq('Pending')
    end

    it 'returns pre-reserved incoming inventory to in_transit' do
      line = create_line
      inventory = create_linked_inventory(status: :pre_reserved, line: line)

      described_class.new(sale_order).call

      expect(inventory.reload).to have_attributes(
        status: 'in_transit',
        sale_order_id: nil,
        sale_order_item_id: nil,
        sold_price: nil
      )
    end

    it 'cancels a linked preorder while preserving order-line history' do
      line = create_line(preorder_quantity: 1)
      reservation = create(
        :preorder_reservation,
        sale_order: sale_order,
        sale_order_item: line,
        product: product,
        user: user,
        status: :pending
      )

      described_class.new(sale_order).call

      expect(reservation.reload).to be_cancelled
      expect(reservation.cancelled_at).to be_present
      expect(reservation.sale_order).to eq(sale_order)
      expect(reservation.sale_order_item).to eq(line)
    end

    it 'cancels a mixed unpaid order without confusing on-hand and incoming states' do
      on_hand_line = create_line
      incoming_line = create_line(line_product: other_product)
      reserved = create_linked_inventory(status: :reserved, line: on_hand_line)
      pre_reserved = create_linked_inventory(
        status: :pre_reserved,
        line: incoming_line,
        inventory_product: other_product
      )
      reservation = create(
        :preorder_reservation,
        sale_order: sale_order,
        sale_order_item: incoming_line,
        product: other_product,
        user: user,
        status: :assigned
      )

      described_class.new(sale_order).call

      expect(sale_order.reload.status).to eq('Canceled')
      expect(reserved.reload.status).to eq('available')
      expect(pre_reserved.reload.status).to eq('in_transit')
      expect(reservation.reload).to be_cancelled
    end

    it 'blocks sold inventory without releasing or rewriting it' do
      line = create_line
      inventory = create_linked_inventory(status: :sold, line: line)

      expect { described_class.new(sale_order).call }
        .to raise_error(described_class::CancellationBlocked, /vendido o pre-vendido/)

      expect(sale_order.reload.status).to eq('Pending')
      expect(inventory.reload.status).to eq('sold')
      expect(inventory.sale_order).to eq(sale_order)
      expect(inventory.sale_order_item).to eq(line)
    end

    it 'blocks pre-sold inventory without making it available or in_transit' do
      line = create_line
      inventory = create_linked_inventory(status: :pre_sold, line: line)

      expect { described_class.new(sale_order).call }
        .to raise_error(described_class::CancellationBlocked, /vendido o pre-vendido/)

      expect(sale_order.reload.status).to eq('Pending')
      expect(inventory.reload.status).to eq('pre_sold')
      expect(inventory.sale_order).to eq(sale_order)
      expect(inventory.sale_order_item).to eq(line)
    end

    it 'blocks a shipped customer order from the simple cancellation path' do
      sale_order.update_columns(status: 'In Transit')
      inventory = create_linked_inventory(status: :reserved)

      expect { described_class.new(sale_order).call }
        .to raise_error(described_class::CancellationBlocked, /enviada o entregada/)

      expect(sale_order.reload.status).to eq('In Transit')
      expect(inventory.reload.status).to eq('reserved')
    end

    it 'blocks an unpaid confirmed order because the simple path is pending-only' do
      sale_order.update_columns(status: 'Confirmed')
      inventory = create_linked_inventory(status: :reserved)

      expect { described_class.new(sale_order).call }
        .to raise_error(described_class::CancellationBlocked, /Solo una orden pendiente/)

      expect(sale_order.reload.status).to eq('Confirmed')
      expect(inventory.reload.status).to eq('reserved')
    end

    it 'blocks a delivered order from the simple cancellation path' do
      sale_order.update_columns(status: 'Delivered')
      inventory = create_linked_inventory(status: :sold)

      expect { described_class.new(sale_order).call }
        .to raise_error(described_class::CancellationBlocked, /enviada o entregada/)

      expect(sale_order.reload.status).to eq('Delivered')
      expect(inventory.reload.status).to eq('sold')
    end

    it 'blocks a fully paid order for refund review without changing its Payment' do
      payment = create(:payment, sale_order: sale_order, amount: 100, status: 'Completed')
      inventory = create_linked_inventory(status: :sold)

      expect { described_class.new(sale_order.reload).call }
        .to raise_error(described_class::CancellationBlocked, /revisión de pago y reembolso/)

      expect(sale_order.reload.status).not_to eq('Canceled')
      expect(payment.reload.status).to eq('Completed')
      expect(inventory.reload.status).to eq('sold')
    end

    it 'blocks a partially paid pending order for refund review' do
      line = create_line
      inventory = create_linked_inventory(status: :reserved, line: line)
      payment = create(:payment, sale_order: sale_order, amount: 40, status: 'Completed')

      expect(sale_order.reload.status).to eq('Pending')
      expect { described_class.new(sale_order).call }
        .to raise_error(described_class::CancellationBlocked, /revisión de pago y reembolso/)

      expect(sale_order.reload.status).to eq('Pending')
      expect(payment.reload.status).to eq('Completed')
      expect(inventory.reload.status).to eq('reserved')
    end

    it 'is idempotent when the same cancellation is repeated' do
      line = create_line(preorder_quantity: 1)
      inventory = create_linked_inventory(status: :reserved, line: line)
      reservation = create(
        :preorder_reservation,
        sale_order: sale_order,
        sale_order_item: line,
        product: product,
        user: user,
        status: :pending
      )
      allow(Preorders::PreorderAllocator).to receive(:batch_allocate).and_return(product.id => true)

      service = described_class.new(sale_order)
      service.call
      first_inventory_update = inventory.reload.updated_at
      first_cancellation_time = reservation.reload.cancelled_at

      travel 1.minute do
        service.call
      end

      expect(inventory.reload.updated_at).to eq(first_inventory_update)
      expect(reservation.reload.cancelled_at).to eq(first_cancellation_time)
      expect(Preorders::PreorderAllocator).to have_received(:batch_allocate).once
    end

    it "never modifies another order's inventory, including conflicting line ownership" do
      current_line = create_line
      current_inventory = create_linked_inventory(status: :reserved, line: current_line)
      other_order = create(:sale_order, status: 'Pending')
      other_line = create_line(order: other_order, line_product: other_product)
      other_inventory = create_linked_inventory(
        status: :reserved,
        order: other_order,
        line: other_line,
        inventory_product: other_product
      )
      conflicting_inventory = create_linked_inventory(
        status: :reserved,
        order: other_order,
        line: current_line,
        inventory_product: product
      )

      expect { described_class.new(sale_order).call }
        .to raise_error(described_class::CancellationBlocked, /propiedad del inventario/)

      expect(sale_order.reload.status).to eq('Pending')
      expect(current_inventory.reload.status).to eq('reserved')
      expect(other_inventory.reload).to have_attributes(
        status: 'reserved',
        sale_order_id: other_order.id,
        sale_order_item_id: other_line.id
      )
      expect(conflicting_inventory.reload).to have_attributes(
        status: 'reserved',
        sale_order_id: other_order.id,
        sale_order_item_id: current_line.id
      )
    end

    it 'rolls inventory and preorder changes back if the order update fails' do
      line = create_line(preorder_quantity: 1)
      inventory = create_linked_inventory(status: :reserved, line: line)
      reservation = create(
        :preorder_reservation,
        sale_order: sale_order,
        sale_order_item: line,
        product: product,
        user: user,
        status: :pending
      )
      allow(sale_order).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(sale_order))

      expect { described_class.new(sale_order).call }.to raise_error(ActiveRecord::RecordInvalid)

      expect(inventory.reload.status).to eq('reserved')
      expect(reservation.reload).to be_pending
      expect(sale_order.reload.status).to eq('Pending')
    end
  end
end
