# frozen_string_literal: true

require 'rails_helper'

# The preorder queue is a FIFO commitment ledger, not a report. Older committed
# demand must be backed by new supply before that supply is offered to anyone
# else. These examples pin the business lifecycle:
#
#   pending preorder -> pre_reserved (inbound) -> reserved (received) -> sold
#
# and prove that free inventory is only ever "known supply MINUS older
# committed demand".
RSpec.describe 'Preorder supply queue', type: :service do
  let(:product) do
    create(
      :product,
      skip_seed_inventory: true,
      preorder_available: true,
      backorder_allowed: false,
      status: 'active'
    )
  end

  # Demand that exists with no Inventory row anywhere: the canonical preorder.
  def preorder_demand(quantity:, reserved_at: Time.current)
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
      reserved_at: reserved_at
    )
    [order, line, reservation]
  end

  def inbound_purchase_order(quantity, status: 'In Transit')
    purchase_order = create(:purchase_order, status: status)
    item = create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: quantity)
    [purchase_order, item]
  end

  def free_inbound
    Inventory.customer_in_transit.where(product: product).count
  end

  def backed_inbound
    Inventory.where(product: product, status: :pre_reserved).count
  end

  def pending_demand
    PreorderReservation.pending.where(product: product).sum(:quantity).to_i
  end

  describe 'canonical preorder case' do
    it 'backs older pending demand from brand-new inbound supply before freeing the rest' do
      order, line, reservation = preorder_demand(quantity: 3, reserved_at: 2.days.ago)

      # Stage 1: unbacked preorder. No Inventory row exists at all.
      expect(Inventory.where(product: product).count).to eq(0)
      expect(pending_demand).to eq(3)

      inbound_purchase_order(10)

      # Stage 2: backed inbound preorder.
      backed = Inventory.where(product: product, status: :pre_reserved)
      aggregate_failures do
        expect(backed.count).to eq(3)
        expect(backed.pluck(:sale_order_id).uniq).to eq([order.id])
        expect(backed.pluck(:sale_order_item_id).uniq).to eq([line.id])
        expect(free_inbound).to eq(7)
        expect(pending_demand).to eq(0)
        expect(reservation.reload).to be_assigned
        expect(line.reload.preorder_quantity).to eq(0)
        # The forbidden intermediate state: 10 free inbound + 3 still pending.
        expect(Inventory.customer_sellable.where(product: product).count).to eq(7)
      end
    end

    it 'never leaves supply free while older demand is still pending' do
      preorder_demand(quantity: 3, reserved_at: 2.days.ago)
      inbound_purchase_order(2)

      aggregate_failures do
        expect(backed_inbound).to eq(2)
        expect(free_inbound).to eq(0)
        expect(pending_demand).to eq(1)
      end
    end
  end

  describe 'FIFO ordering across multiple commitments' do
    it 'fills A then B then C by reserved_at, never by newest order' do
      _oa, line_a, res_a = preorder_demand(quantity: 4, reserved_at: 3.days.ago)
      _ob, line_b, res_b = preorder_demand(quantity: 3, reserved_at: 2.days.ago)
      _oc, line_c, res_c = preorder_demand(quantity: 5, reserved_at: 1.day.ago)

      inbound_purchase_order(8)

      aggregate_failures do
        expect(line_a.reload.inventory_units.where(status: :pre_reserved).count).to eq(4)
        expect(line_b.reload.inventory_units.where(status: :pre_reserved).count).to eq(3)
        expect(line_c.reload.inventory_units.where(status: :pre_reserved).count).to eq(1)

        expect(res_a.reload).to be_assigned
        expect(res_b.reload).to be_assigned

        expect(backed_inbound).to eq(8)
        expect(free_inbound).to eq(0)

        # Only C, the newest commitment, keeps a remainder.
        expect(pending_demand).to eq(4)
        expect(PreorderReservation.pending.where(sale_order_item: line_c).sum(:quantity)).to eq(4)
        expect(line_c.reload.preorder_quantity).to eq(4)
        expect(res_c.reload.quantity).to eq(1)
      end
    end
  end

  describe 'successive purchase orders' do
    it 'advances the queue without skipping an earlier commitment' do
      _order, line, _reservation = preorder_demand(quantity: 12, reserved_at: 3.days.ago)

      inbound_purchase_order(5)
      aggregate_failures do
        expect(backed_inbound).to eq(5)
        expect(pending_demand).to eq(7)
        expect(free_inbound).to eq(0)
      end

      inbound_purchase_order(4)
      aggregate_failures do
        expect(backed_inbound).to eq(9)
        expect(pending_demand).to eq(3)
        expect(free_inbound).to eq(0)
      end

      inbound_purchase_order(10)
      aggregate_failures do
        expect(backed_inbound).to eq(12)
        expect(pending_demand).to eq(0)
        expect(free_inbound).to eq(7)
        expect(line.reload.inventory_units.where(status: :pre_reserved).count).to eq(12)
        expect(line.preorder_quantity).to eq(0)
      end
    end
  end

  describe 'purchase order quantity increase' do
    it 'treats only the newly created rows as new supply and keeps backed pieces intact' do
      _order, line, _reservation = preorder_demand(quantity: 8, reserved_at: 2.days.ago)
      _purchase_order, item = inbound_purchase_order(5)

      backed_ids = Inventory.where(product: product, status: :pre_reserved).order(:id).pluck(:id)
      expect(backed_ids.size).to eq(5)
      expect(pending_demand).to eq(3)

      item.update!(quantity: 10)

      aggregate_failures do
        # The 5 already-backed pieces keep their identity and their customer.
        still_backed = Inventory.where(id: backed_ids)
        expect(still_backed.where(status: :pre_reserved).count).to eq(5)
        expect(still_backed.pluck(:sale_order_item_id).uniq).to eq([line.id])

        # The 5 additional pieces go to the remaining older demand first.
        expect(backed_inbound).to eq(8)
        expect(pending_demand).to eq(0)
        expect(free_inbound).to eq(2)
        expect(Inventory.where(product: product).count).to eq(10)
      end
    end
  end

  describe 'purchase order quantity reduction' do
    it 'refuses to strip inventory that already backs committed demand' do
      preorder_demand(quantity: 5, reserved_at: 2.days.ago)
      _purchase_order, item = inbound_purchase_order(5)

      expect(backed_inbound).to eq(5)
      expect(free_inbound).to eq(0)

      # No free units exist, so the guard must block the reduction outright
      # rather than deleting a customer's committed piece.
      expect(item.update(quantity: 2)).to be(false)

      aggregate_failures do
        expect(item.reload.quantity).to eq(5)
        expect(backed_inbound).to eq(5)
        expect(pending_demand).to eq(0)
      end
    end

    # Antes esto reventaba: `inventory_events` tiene llave foránea a
    # `inventories` sin cascade, así que destruir una pieza con auditoría
    # lanzaba InvalidForeignKey. Ahora la pieza libre sobrante se retira a
    # :scrap en vez de destruirse, y el rastro sobrevive.
    it 'trims free inbound units carrying audit history without touching committed demand' do
      preorder_demand(quantity: 2, reserved_at: 2.days.ago)
      _purchase_order, item = inbound_purchase_order(6)

      expect(backed_inbound).to eq(2)
      expect(free_inbound).to eq(4)

      expect { item.update!(quantity: 3) }.not_to raise_error

      aggregate_failures do
        # La demanda vieja sigue respaldada; sólo se retiró suministro libre.
        expect(backed_inbound).to eq(2)
        expect(free_inbound).to eq(1)
        expect(pending_demand).to eq(0)
        expect(Inventory.where(product: product, status: :scrap).count).to eq(3)
      end
    end
  end

  describe 'purchase order cancellation' do
    it 'does not silently scrap inventory that backs a customer commitment' do
      _order, line, _reservation = preorder_demand(quantity: 3, reserved_at: 2.days.ago)
      purchase_order, _item = inbound_purchase_order(5)

      expect(backed_inbound).to eq(3)
      expect(free_inbound).to eq(2)

      purchase_order.update!(status: 'Canceled')

      aggregate_failures do
        # Committed pieces survive; only the free inbound units are scrapped.
        expect(Inventory.where(product: product, status: :pre_reserved).count).to eq(3)
        expect(line.reload.inventory_units.where(status: :pre_reserved).count).to eq(3)
        expect(Inventory.where(product: product, status: :scrap).count).to eq(2)
        expect(free_inbound).to eq(0)
      end
    end
  end

  describe 'lifecycle through receipt' do
    it 'moves backed inbound demand to reserved on delivery without losing the customer' do
      order, line, _reservation = preorder_demand(quantity: 3, reserved_at: 2.days.ago)
      purchase_order, _item = inbound_purchase_order(5)

      expect(backed_inbound).to eq(3)

      purchase_order.update!(status: 'Delivered')

      reserved = Inventory.where(product: product, status: :reserved)
      aggregate_failures do
        # Stage 3: received preorder, still tied to the original order.
        expect(reserved.count).to eq(3)
        expect(reserved.pluck(:sale_order_id).uniq).to eq([order.id])
        expect(reserved.pluck(:sale_order_item_id).uniq).to eq([line.id])
        expect(Inventory.where(product: product, status: :pre_reserved).count).to eq(0)
        # Received-but-unlocated free stock is not yet customer sellable.
        expect(Inventory.where(product: product, status: :available).count).to eq(2)
        expect(Inventory.customer_sellable.where(product: product).count).to eq(0)
      end
    end
  end

  describe 'canonical demand accounting' do
    it 'keeps reservation quantity and line preorder_quantity in agreement' do
      _order, line, _reservation = preorder_demand(quantity: 9, reserved_at: 2.days.ago)
      inbound_purchase_order(4)

      reservations = PreorderReservation.where(sale_order_item: line)
      aggregate_failures do
        # Total commitment is conserved: nothing invented, nothing lost.
        expect(reservations.sum(:quantity)).to eq(9)
        expect(reservations.assigned.sum(:quantity)).to eq(4)
        expect(reservations.pending.sum(:quantity)).to eq(5)
        # The two representations of "still waiting" must agree.
        expect(line.reload.preorder_quantity).to eq(reservations.pending.sum(:quantity))
      end
    end

    it 'derives backing traceability through inventory rather than a direct join' do
      _order, line, _reservation = preorder_demand(quantity: 2, reserved_at: 2.days.ago)
      purchase_order, item = inbound_purchase_order(5)

      backing = line.reload.inventory_units.where(status: :pre_reserved)
      aggregate_failures do
        expect(backing.count).to eq(2)
        expect(backing.pluck(:purchase_order_id).uniq).to eq([purchase_order.id])
        expect(backing.pluck(:purchase_order_item_id).uniq).to eq([item.id])
      end
    end
  end
end
