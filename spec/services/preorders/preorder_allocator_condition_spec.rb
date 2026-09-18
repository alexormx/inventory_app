# frozen_string_literal: true

require 'rails_helper'

# Condition scoping for preorder supply.
#
# Preorder demand carries a condition: it lives on the SaleOrderItem
# (#item_condition), and InventoryServices::ReserveSaleOrderItem already
# consumes only inventory of that condition. The allocator's *supply budget*
# was the blind part - it counted every customer-sellable row for the product
# regardless of condition, so a unit of one condition's supply could authorise,
# and be spent on, another condition's demand.
RSpec.describe Preorders::PreorderAllocator do
  let(:location) { create(:inventory_location) }
  let(:product)  { create(:product, skip_seed_inventory: true, preorder_available: true) }

  # A preorder line plus its pending reservation, for one condition.
  def preorder_demand(condition:, quantity: 1, reserved_at: Time.current)
    order = create(:sale_order)
    line = create(
      :sale_order_item,
      sale_order: order,
      product: product,
      quantity: quantity,
      preorder_quantity: quantity,
      item_condition: condition,
      unit_cost: 40,
      unit_selling_price: 100,
      unit_final_price: 100,
      total_line_cost: 40 * quantity
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
    [line, reservation]
  end

  # Existing stock that is already on the shelf. update_columns bypasses the
  # publication callback so the fixture itself does not trigger allocation.
  def existing_available(condition:)
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(
      status: Inventory.statuses[:available],
      item_condition: Inventory.item_conditions[condition.to_s],
      inventory_location_id: location.id
    )
    inventory
  end

  # A piece that becomes sellable now, firing the real publication callback
  # (Inventory#reconcile_preorders_before_publication -> allocator, units: 1).
  def publish_available(condition:)
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(item_condition: Inventory.item_conditions[condition.to_s])
    inventory.reload.update!(status: :available, inventory_location: location)
    inventory
  end

  # Piezas ya compradas y en camino: siguen contando como oferta de preventa
  # (customer_sellable), que es la semántica que este PR preserva.
  def existing_in_transit(condition:)
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(
      status: Inventory.statuses[:in_transit],
      item_condition: Inventory.item_conditions[condition.to_s]
    )
    inventory
  end

  def conditions_of(line)
    line.reload.inventory_units.map(&:item_condition).uniq
  end

  # A self-contained product asking for 5 brand_new with only 4 in stock,
  # optionally buried under stock of every other condition. Returns the outcome
  # so two scenarios can be compared directly.
  def build_scenario(unrelated_stock:)
    subject_product = create(:product, skip_seed_inventory: true, preorder_available: true)
    order = create(:sale_order)
    line = create(
      :sale_order_item,
      sale_order: order, product: subject_product,
      quantity: 5, preorder_quantity: 5, item_condition: :brand_new,
      unit_cost: 40, unit_selling_price: 100, unit_final_price: 100, total_line_cost: 200
    )
    create(
      :preorder_reservation,
      product: subject_product, user: order.user, sale_order: order,
      sale_order_item: line, quantity: 5
    )

    stock = lambda do |condition, status|
      inventory = create(:inventory, product: subject_product, status: :damaged)
      inventory.update_columns(
        status: Inventory.statuses[status.to_s],
        item_condition: Inventory.item_conditions[condition.to_s],
        inventory_location_id: (status == :available ? location.id : nil)
      )
    end

    4.times { stock.call(:brand_new, :available) }
    if unrelated_stock
      100.times { stock.call(:mint, :available) }
      100.times { stock.call(:good, :in_transit) }
      50.times  { stock.call(:loose, :available) }
    end

    assigned = described_class.new(subject_product).call
    {
      assigned: assigned,
      preorder_remaining: line.reload.preorder_quantity,
      conditions: line.reload.inventory_units.map(&:item_condition).uniq
    }
  end

  describe 'matching condition' do
    it 'allocates brand_new demand from brand_new supply' do
      line, reservation = preorder_demand(condition: :brand_new, quantity: 2)
      2.times { existing_available(condition: :brand_new) }

      expect(described_class.new(product).call).to eq(2)
      expect(reservation.reload).to be_assigned
      expect(line.reload.preorder_quantity).to eq(0)
      expect(conditions_of(line)).to eq(['brand_new'])
    end

    it 'allocates mint demand from mint supply' do
      line, reservation = preorder_demand(condition: :mint, quantity: 2)
      2.times { existing_available(condition: :mint) }

      expect(described_class.new(product).call).to eq(2)
      expect(reservation.reload).to be_assigned
      expect(conditions_of(line)).to eq(['mint'])
    end
  end

  describe 'cross-condition isolation' do
    it 'does not let mint supply satisfy brand_new demand' do
      _line, reservation = preorder_demand(condition: :brand_new)
      mint = existing_available(condition: :mint)

      expect(described_class.new(product).call).to eq(0)
      expect(reservation.reload).to be_pending
      expect(mint.reload.sale_order_item_id).to be_nil
    end

    it 'does not let good supply satisfy brand_new demand' do
      _line, reservation = preorder_demand(condition: :brand_new)
      good = existing_available(condition: :good)

      expect(described_class.new(product).call).to eq(0)
      expect(reservation.reload).to be_pending
      expect(good.reload.sale_order_item_id).to be_nil
    end

    it 'does not let brand_new supply satisfy mint demand' do
      _line, reservation = preorder_demand(condition: :mint)
      brand_new = existing_available(condition: :brand_new)

      expect(described_class.new(product).call).to eq(0)
      expect(reservation.reload).to be_pending
      expect(brand_new.reload.sale_order_item_id).to be_nil
    end
  end

  describe 'mixed inventory' do
    it 'caps eligible supply at the requested condition, ignoring abundant others' do
      line, _reservation = preorder_demand(condition: :brand_new, quantity: 22)
      2.times  { existing_available(condition: :brand_new) }
      20.times { existing_available(condition: :mint) }

      expect(described_class.new(product).call).to eq(2)
      expect(line.reload.preorder_quantity).to eq(20)
      expect(conditions_of(line)).to eq(['brand_new'])
    end
  end

  describe 'boundary quantities' do
    it 'fills demand exactly when the matching condition covers it' do
      line, reservation = preorder_demand(condition: :brand_new, quantity: 3)
      3.times { existing_available(condition: :brand_new) }

      expect(described_class.new(product).call).to eq(3)
      expect(reservation.reload).to be_assigned
      expect(line.reload.preorder_quantity).to eq(0)
    end

    it 'leaves the shortfall pending when the matching condition is short by one' do
      line, _reservation = preorder_demand(condition: :brand_new, quantity: 3)
      2.times  { existing_available(condition: :brand_new) }
      20.times { existing_available(condition: :mint) }

      expect(described_class.new(product).call).to eq(2)
      expect(line.reload.preorder_quantity).to eq(1)
      expect(PreorderReservation.pending.where(sale_order_item: line).sum(:quantity)).to eq(1)
      expect(conditions_of(line)).to eq(['brand_new'])
    end
  end

  describe 'in transit' do
    it 'still counts same-condition in-transit stock as preorder supply' do
      line, reservation = preorder_demand(condition: :brand_new, quantity: 2)
      2.times { existing_in_transit(condition: :brand_new) }

      expect(described_class.new(product).call).to eq(2)
      expect(reservation.reload).to be_assigned
      expect(conditions_of(line)).to eq(['brand_new'])
      expect(line.reload.inventory_units.map(&:status).uniq).to eq(['pre_reserved'])
    end

    it 'never counts different-condition in-transit stock as preorder supply' do
      _line, reservation = preorder_demand(condition: :brand_new)
      mint = existing_in_transit(condition: :mint)

      expect(described_class.new(product).call).to eq(0)
      expect(reservation.reload).to be_pending
      expect(mint.reload.sale_order_item_id).to be_nil
    end
  end

  it 'spends a newly available unit on demand for that same condition' do
    _mint_line, mint_reservation = preorder_demand(condition: :mint, reserved_at: 2.hours.ago)
    brand_new_line, brand_new_reservation = preorder_demand(condition: :brand_new, reserved_at: 1.hour.ago)
    existing_available(condition: :mint)

    brand_new_piece = publish_available(condition: :brand_new)

    # The brand_new piece must satisfy the brand_new reservation, even though an
    # older mint reservation sits ahead of it in the FIFO queue.
    expect(brand_new_piece.reload.sale_order_item_id).to eq(brand_new_line.id)
    expect(brand_new_reservation.reload).to be_assigned
    # The older mint reservation is not served by brand_new supply.
    expect(mint_reservation.reload).to be_pending
  end

  # newly_available_units has meant ONE shared quantity budget for this call
  # since the class was born (a81acdaa) and when it became optional (b81abac8).
  # Condition scoping narrows *which* demand may spend it; it must never widen
  # the total. Without a shared pool, N units would grant N per condition.
  describe 'newly_available_units as a shared pool' do
    it 'never hands out more than the units it was given, across all conditions' do
      preorder_demand(condition: :brand_new, quantity: 2)
      preorder_demand(condition: :mint, quantity: 2)
      preorder_demand(condition: :good, quantity: 2)
      5.times { existing_available(condition: :brand_new) }
      5.times { existing_available(condition: :mint) }
      5.times { existing_available(condition: :good) }

      expect(described_class.new(product, newly_available_units: 2).call).to eq(2)
    end

    it 'caps a single oversized reservation at the units given' do
      line, _reservation = preorder_demand(condition: :brand_new, quantity: 5)
      5.times { existing_available(condition: :brand_new) }

      # Supply and demand both allow 5; the call was only granted 2 units.
      expect(described_class.new(product, newly_available_units: 2).call).to eq(2)
      expect(line.reload.preorder_quantity).to eq(3)
    end

    it 'caps an explicit condition by both the units and that condition supply' do
      line, _reservation = preorder_demand(condition: :brand_new, quantity: 5)
      2.times   { existing_available(condition: :brand_new) }
      100.times { existing_available(condition: :mint) }

      # units=5 but only 2 brand_new exist -> 2.
      expect(described_class.new(product, newly_available_units: 5, condition: 'brand_new').call).to eq(2)
      expect(conditions_of(line)).to eq(['brand_new'])
    end

    it 'gives an explicit condition nothing when only other conditions have supply' do
      _line, reservation = preorder_demand(condition: :brand_new)
      100.times { existing_available(condition: :mint) }

      expect(described_class.new(product, newly_available_units: 5, condition: 'brand_new').call).to eq(0)
      expect(reservation.reload).to be_pending
    end

    it 'accepts the condition as a symbol, string or enum integer alike' do
      preorder_demand(condition: :brand_new, quantity: 3)
      3.times { existing_available(condition: :brand_new) }

      expect(described_class.new(product, newly_available_units: 1, condition: :brand_new).call).to eq(1)
      expect(described_class.new(product, newly_available_units: 1, condition: 'brand_new').call).to eq(1)
      expect(described_class.new(product, newly_available_units: 1, condition: 0).call).to eq(1)
    end
  end

  # The invariant that matters most: supply of other conditions is simply not
  # an input to a given condition's outcome.
  describe 'condition independence invariant' do
    # Two identical products, except one is drowned in stock of every other
    # condition. The brand_new outcome must be byte-for-byte the same.
    it 'is unaffected by adding arbitrary stock of every other condition' do
      control = build_scenario(unrelated_stock: false)
      flooded = build_scenario(unrelated_stock: true)

      expect(flooded[:assigned]).to eq(control[:assigned])
      expect(flooded[:preorder_remaining]).to eq(control[:preorder_remaining])
      expect(flooded[:conditions]).to eq(control[:conditions])
      expect(control[:assigned]).to eq(4)
    end

    it 'leaves the shortfall unfilled no matter how much unrelated stock exists' do
      line, _reservation = preorder_demand(condition: :brand_new, quantity: 5)
      4.times   { existing_available(condition: :brand_new) }
      100.times { existing_available(condition: :mint) }
      100.times { existing_available(condition: :good) }

      expect(described_class.new(product).call).to eq(4)
      expect(line.reload.preorder_quantity).to eq(1)
      expect(conditions_of(line)).to eq(['brand_new'])
      expect(PreorderReservation.pending.where(sale_order_item: line).sum(:quantity)).to eq(1)
    end

    it 'sums exactly the matching condition across available and in-transit' do
      line, reservation = preorder_demand(condition: :brand_new, quantity: 5)
      2.times  { existing_available(condition: :brand_new) }
      3.times  { existing_in_transit(condition: :brand_new) }
      50.times { existing_available(condition: :mint) }
      50.times { existing_in_transit(condition: :mint) }

      # 2 available + 3 in-transit of the requested condition = 5, never 105.
      expect(described_class.new(product).call).to eq(5)
      expect(reservation.reload).to be_assigned
      expect(line.reload.preorder_quantity).to eq(0)
      expect(conditions_of(line)).to eq(['brand_new'])
    end

    it 'ignores wrong-condition in-transit stock when the match is short' do
      line, _reservation = preorder_demand(condition: :brand_new, quantity: 3)
      1.times  { existing_available(condition: :brand_new) }
      50.times { existing_in_transit(condition: :good) }

      expect(described_class.new(product).call).to eq(1)
      expect(line.reload.preorder_quantity).to eq(2)
      expect(conditions_of(line)).to eq(['brand_new'])
    end
  end

  describe 'record selection under adversarial ordering' do
    it 'skips older wrong-condition rows and takes the newer matching ones' do
      line, _reservation = preorder_demand(condition: :good, quantity: 2)
      # Older, wrong condition - would win any FIFO that ignored condition.
      older = Array.new(5) { existing_available(condition: :brand_new) }
      newer = Array.new(2) { existing_available(condition: :good) }

      expect(described_class.new(product).call).to eq(2)
      expect(conditions_of(line)).to eq(['good'])
      expect(line.reload.inventory_units.map(&:id)).to match_array(newer.map(&:id))
      expect(Inventory.where(id: older.map(&:id)).pluck(:sale_order_item_id).uniq).to eq([nil])
    end

    it 'allocates zero and touches nothing when the requested condition has no supply' do
      _line, reservation = preorder_demand(condition: :good, quantity: 2)
      untouched = Array.new(5) { existing_available(condition: :brand_new) }

      expect(described_class.new(product).call).to eq(0)
      expect(reservation.reload).to be_pending
      expect(Inventory.where(id: untouched.map(&:id)).pluck(:sale_order_item_id).uniq).to eq([nil])
      expect(Inventory.where(id: untouched.map(&:id)).pluck(:status).uniq).to eq(['available'])
    end
  end
end
