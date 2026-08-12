# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inventories::VerifyPhysicalUnitService, type: :service do
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:actor) { create(:user, :admin, name: 'Inventory Admin') }
  let(:location) { create(:inventory_location) }
  let(:inventory) { create(:inventory, product: product, status: :available, inventory_location: nil) }

  def verify(record, result:, actor:, **options)
    snapshot = options.delete(:snapshot) || described_class.snapshot_for(record)
    described_class.call(
      inventory_id: record.id,
      result: result,
      actor: actor,
      expected_snapshot: snapshot,
      **options
    )
  end

  describe '.snapshot_for' do
    let(:precise_updated_at) { Time.utc(2026, 8, 12, 12, 34, 56, 123_456) }

    before do
      inventory.update_column(:updated_at, precise_updated_at)
      inventory.reload
    end

    it 'returns every protected field with six-digit timestamp precision' do
      snapshot = described_class.snapshot_for(inventory)

      expect(snapshot).to eq(
        updated_at: '2026-08-12T12:34:56.123456Z',
        status: 'available',
        inventory_location_id: nil,
        sale_order_id: nil,
        sale_order_item_id: nil,
        product_id: product.id
      )
    end

    it 'round-trips through ordinary JSON without a false stale conflict' do
      transported_snapshot = JSON.parse(described_class.snapshot_for(inventory).to_json)

      result = verify(
        inventory,
        result: :found,
        location_id: location.id,
        actor: actor,
        snapshot: transported_snapshot
      )

      expect(result.inventory.reload.inventory_location).to eq(location)
    end

    it 'accepts controller-like string keys, numeric IDs, and blank optional IDs' do
      transported_snapshot = described_class.snapshot_for(inventory).stringify_keys.merge(
        'inventory_location_id' => '',
        'sale_order_id' => '',
        'sale_order_item_id' => '',
        'product_id' => product.id.to_s
      )

      result = verify(
        inventory,
        result: :found,
        location_id: location.id.to_s,
        actor: actor,
        snapshot: transported_snapshot
      )

      expect(result.inventory.reload.inventory_location).to eq(location)
    end

    it 'detects a real timestamp change within the same millisecond' do
      snapshot = described_class.snapshot_for(inventory)
      inventory.update_column(:updated_at, Time.utc(2026, 8, 12, 12, 34, 56, 123_789))

      expect do
        verify(inventory, result: :found, location_id: location.id, actor: actor, snapshot: snapshot)
      end.to raise_error(described_class::StaleInventory) do |error|
        expect(error.changed_fields).to contain_exactly('updated_at')
      end

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end
  end

  describe 'available inventory found at a physical location' do
    it 'locks the exact row, assigns the location, records the audit event, and becomes customer on-hand' do
      expected_updated_at = inventory.updated_at.utc.iso8601(6)
      service_result = nil
      lock_queries = []
      subscriber = lambda do |_name, _start, _finish, _id, payload|
        lock_queries << payload[:sql] if payload[:sql].match?(/FOR UPDATE/i)
      end

      expect do
        ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
          service_result = verify(
            inventory,
            result: :found,
            location_id: location.id,
            actor: actor,
            notes: 'Found in the labeled bin'
          )
        end
      end.to change { InventoryEvent.where(event_type: 'physical_inventory_verification').count }.by(1)

      verified = inventory.reload
      event = service_result.event.reload
      expect(verified).to be_available
      expect(verified.inventory_location).to eq(location)
      expect(Inventory.customer_on_hand).to include(verified)
      expect(service_result.inventory).to eq(verified)
      expect(lock_queries.grep(/FROM "inventories".*FOR UPDATE/i)).not_to be_empty
      expect(event.inventory).to eq(verified)
      expect(event.product).to eq(product)
      expect(event.metadata).to include(
        'result' => 'found',
        'notes' => 'Found in the labeled bin',
        'actor_id' => actor.id,
        'actor_email' => actor.email,
        'actor_name' => actor.name,
        'previous_status' => 'available',
        'new_status' => 'available',
        'previous_location_id' => nil,
        'new_location_id' => location.id,
        'product_id' => product.id,
        'expected_updated_at' => expected_updated_at,
        'verified_inventory_updated_at' => verified.updated_at.utc.iso8601(6)
      )
    end

    it 'preserves a pre-existing order link instead of silently releasing it' do
      sale_order = create(:sale_order)
      sale_item = create(:sale_order_item, sale_order: sale_order, product: product)
      linked = create(:inventory, product: product, status: :available, inventory_location: nil)
      linked.update_columns(
        sale_order_id: sale_order.id,
        sale_order_item_id: sale_item.id,
        sold_price: 125,
        updated_at: Time.current
      )

      verify(linked.reload, result: :found, location_id: location.id, actor: actor)

      expect(linked.reload).to be_available
      expect(linked.inventory_location).to eq(location)
      expect(linked.sale_order).to eq(sale_order)
      expect(linked.sale_order_item).to eq(sale_item)
      expect(linked.sold_price).to eq(125.to_d)
      expect(Inventory.customer_on_hand).not_to include(linked)
    end
  end

  describe 'reserved inventory found at a physical location' do
    it 'preserves the reservation, condition, prices, and purchase provenance' do
      purchase_order = create(:purchase_order, status: 'Delivered')
      purchase_item = create(:purchase_order_item, purchase_order: purchase_order, product: product)
      sale_order = create(:sale_order)
      sale_item = create(
        :sale_order_item,
        sale_order: sale_order,
        product: product,
        unit_selling_price: 175,
        unit_final_price: 165
      )
      reserved = create(
        :inventory,
        product: product,
        purchase_order: purchase_order,
        purchase_order_item: purchase_item,
        sale_order: sale_order,
        sale_order_item: sale_item,
        status: :reserved,
        inventory_location: nil,
        item_condition: :mint,
        purchase_cost: 80,
        selling_price: 175,
        sold_price: 165,
        source: 'po_regular',
        notes: 'Reserved unit'
      )
      preserved_attributes = reserved.attributes.slice(
        'product_id', 'purchase_order_id', 'purchase_order_item_id',
        'sale_order_id', 'sale_order_item_id', 'item_condition',
        'purchase_cost', 'selling_price', 'sold_price', 'source', 'notes'
      )

      expect do
        verify(reserved, result: :found, location_id: location.id, actor: actor)
      end.to change { InventoryEvent.where(event_type: 'physical_inventory_verification').count }.by(1)

      verified = reserved.reload
      expect(verified).to be_reserved
      expect(verified.inventory_location).to eq(location)
      expect(verified.attributes.slice(*preserved_attributes.keys)).to eq(preserved_attributes)
      expect(Inventory.customer_on_hand).not_to include(verified)
      expect(InventoryEvent.last.metadata).to include(
        'sale_order_id' => sale_order.id,
        'sale_order_item_id' => sale_item.id,
        'purchase_order_id' => purchase_order.id,
        'purchase_order_item_id' => purchase_item.id
      )
    end
  end

  describe 'available inventory not found in sellable condition' do
    %w[damaged missing].each do |verification_result|
      it "transitions an available unit reported as #{verification_result} and changes no unrelated inventory" do
        unrelated = create(:inventory, product: product, status: :available, inventory_location: nil)
        unrelated_attributes = unrelated.attributes
        expected_status = verification_result == 'damaged' ? 'damaged' : 'lost'

        expect do
          verify(inventory, result: verification_result, actor: actor, notes: 'Counted during aisle audit')
        end.to change { InventoryEvent.where(event_type: 'physical_inventory_verification').count }.by(1)

        verified = inventory.reload
        expect(verified.status).to eq(expected_status)
        expect(verified.inventory_location_id).to be_nil
        expect(unrelated.reload.attributes).to eq(unrelated_attributes)
        expect(InventoryEvent.last.metadata).to include(
          'result' => verification_result,
          'previous_status' => 'available',
          'new_status' => expected_status,
          'new_location_id' => nil
        )
      end
    end
  end

  describe 'reserved inventory requiring order reconciliation' do
    %w[damaged missing].each do |verification_result|
      it "rejects reserved inventory reported as #{verification_result} without changing its order links" do
        sale_order = create(:sale_order)
        sale_item = create(:sale_order_item, sale_order: sale_order, product: product)
        reserved = create(
          :inventory,
          product: product,
          status: :reserved,
          sale_order: sale_order,
          sale_order_item: sale_item,
          inventory_location: nil
        )

        expect do
          verify(reserved, result: verification_result, actor: actor)
        end.to raise_error(described_class::ReservedInventoryRequiresReconciliation)

        expect(reserved.reload).to be_reserved
        expect(reserved.inventory_location_id).to be_nil
        expect(reserved.sale_order).to eq(sale_order)
        expect(reserved.sale_order_item).to eq(sale_item)
        expect(InventoryEvent.where(inventory: reserved, event_type: 'physical_inventory_verification')).to be_empty
      end
    end
  end

  describe 'unsupported current states' do
    %i[in_transit sold damaged lost returned scrap pre_reserved pre_sold marketing].each do |status|
      it "rejects #{status}" do
        record = create(:inventory, product: product, status: status, inventory_location: nil)

        expect do
          verify(record, result: :found, location_id: location.id, actor: actor)
        end.to raise_error(described_class::InvalidInventoryState)

        expect(record.reload.status).to eq(status.to_s)
        expect(InventoryEvent.where(inventory: record, event_type: 'physical_inventory_verification')).to be_empty
      end
    end

    it 'rejects an already located available unit so the service cannot become a relocation editor' do
      located = create(:inventory, product: product, status: :available, inventory_location: location)
      other_location = create(:inventory_location)

      expect do
        verify(located, result: :found, location_id: other_location.id, actor: actor)
      end.to raise_error(described_class::InvalidInventoryState, /already has a physical location/)

      expect(located.reload.inventory_location).to eq(location)
    end
  end

  describe 'location validation' do
    it 'rejects a missing location ID' do
      expect do
        verify(inventory, result: :found, location_id: nil, actor: actor)
      end.to raise_error(described_class::InvalidLocation, /required/)

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects a nonexistent location' do
      expect do
        verify(inventory, result: :found, location_id: -1, actor: actor)
      end.to raise_error(described_class::InvalidLocation, /does not exist/)

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects an inactive location' do
      inactive = create(:inventory_location, :inactive)

      expect do
        verify(inventory, result: :found, location_id: inactive.id, actor: actor)
      end.to raise_error(described_class::InvalidLocation, /inactive/)

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects a non-final location with children' do
      parent = create(:inventory_location, :warehouse)
      create(:inventory_location, :section, parent: parent)

      expect do
        verify(inventory, result: :found, location_id: parent.id, actor: actor)
      end.to raise_error(described_class::InvalidLocation, /final leaf/)

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects a location supplied for damaged or missing results' do
      expect do
        verify(inventory, result: :damaged, location_id: location.id, actor: actor)
      end.to raise_error(described_class::InvalidLocation, /only be supplied/)

      expect(inventory.reload).to be_available
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end
  end

  describe 'stale snapshot protection' do
    it 'rejects a stale updated_at' do
      snapshot = described_class.snapshot_for(inventory)
      travel 1.second do
        inventory.touch
      end

      expect do
        verify(inventory, result: :found, location_id: location.id, actor: actor, snapshot: snapshot)
      end.to raise_error(described_class::StaleInventory) { |error| expect(error.changed_fields).to include('updated_at') }

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects a stale status' do
      snapshot = described_class.snapshot_for(inventory)
      inventory.update!(status: :damaged)

      expect do
        verify(inventory, result: :found, location_id: location.id, actor: actor, snapshot: snapshot)
      end.to raise_error(described_class::StaleInventory) { |error| expect(error.changed_fields).to include('status') }

      expect(inventory.reload).to be_damaged
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects a stale physical location' do
      snapshot = described_class.snapshot_for(inventory)
      inventory.update!(inventory_location: location)
      other_location = create(:inventory_location)

      expect do
        verify(inventory, result: :found, location_id: other_location.id, actor: actor, snapshot: snapshot)
      end.to raise_error(described_class::StaleInventory) { |error| expect(error.changed_fields).to include('inventory_location_id') }

      expect(inventory.reload.inventory_location).to eq(location)
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects a stale SaleOrder link without overwriting the newer relation' do
      first_order = create(:sale_order)
      second_order = create(:sale_order)
      reserved = create(:inventory, product: product, status: :reserved, sale_order: first_order, inventory_location: nil)
      snapshot = described_class.snapshot_for(reserved)
      reserved.update!(sale_order: second_order)

      expect do
        verify(reserved, result: :found, location_id: location.id, actor: actor, snapshot: snapshot)
      end.to raise_error(described_class::StaleInventory) { |error| expect(error.changed_fields).to include('sale_order_id') }

      expect(reserved.reload.sale_order).to eq(second_order)
      expect(reserved.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: reserved)).to be_empty
    end

    it 'rejects a stale SaleOrderItem link without overwriting the newer relation' do
      sale_order = create(:sale_order)
      first_item = create(:sale_order_item, sale_order: sale_order, product: product)
      second_item = create(:sale_order_item, sale_order: sale_order, product: product)
      reserved = create(
        :inventory,
        product: product,
        status: :reserved,
        sale_order: sale_order,
        sale_order_item: first_item,
        inventory_location: nil
      )
      snapshot = described_class.snapshot_for(reserved)
      reserved.update!(sale_order_item: second_item)

      expect do
        verify(reserved, result: :found, location_id: location.id, actor: actor, snapshot: snapshot)
      end.to raise_error(described_class::StaleInventory) { |error| expect(error.changed_fields).to include('sale_order_item_id') }

      expect(reserved.reload.sale_order_item).to eq(second_item)
      expect(reserved.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: reserved)).to be_empty
    end

    it 'rejects a changed product as a tampered snapshot' do
      snapshot = described_class.snapshot_for(inventory)
      replacement_product = create(:product, skip_seed_inventory: true)
      inventory.update!(product: replacement_product)

      expect do
        verify(inventory, result: :found, location_id: location.id, actor: actor, snapshot: snapshot)
      end.to raise_error(described_class::StaleInventory) { |error| expect(error.changed_fields).to include('product_id') }

      expect(inventory.reload.product).to eq(replacement_product)
      expect(inventory.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects a snapshot missing a protected field' do
      snapshot = described_class.snapshot_for(inventory).except(:sale_order_item_id)

      expect do
        verify(inventory, result: :found, location_id: location.id, actor: actor, snapshot: snapshot)
      end.to raise_error(described_class::InvalidSnapshot, /sale_order_item_id/)

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end
  end

  describe 'atomic audit behavior' do
    it 'rolls the inventory update back when event creation fails' do
      original_updated_at = inventory.updated_at
      invalid_event = InventoryEvent.new
      invalid_event.errors.add(:metadata, 'forced failure')
      allow(InventoryEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid_event))

      expect do
        verify(inventory, result: :found, location_id: location.id, actor: actor)
      end.to raise_error(ActiveRecord::RecordInvalid)

      inventory.reload
      expect(inventory).to be_available
      expect(inventory.inventory_location_id).to be_nil
      expect(inventory.updated_at).to eq(original_updated_at)
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end
  end

  describe 'request validation and actor audit' do
    it 'rejects an invalid result without mutation or event' do
      expect do
        verify(inventory, result: :recounted, location_id: location.id, actor: actor)
      end.to raise_error(described_class::InvalidVerificationResult)

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects a missing actor' do
      expect do
        verify(inventory, result: :found, location_id: location.id, actor: nil)
      end.to raise_error(described_class::UnauthorizedActor)

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end

    it 'rejects a non-admin actor' do
      customer = create(:user)

      expect do
        verify(inventory, result: :found, location_id: location.id, actor: customer)
      end.to raise_error(described_class::UnauthorizedActor)

      expect(inventory.reload.inventory_location_id).to be_nil
      expect(InventoryEvent.where(inventory: inventory)).to be_empty
    end
  end

  describe 'concurrent verification' do
    it 'allows only one attempt from a shared snapshot and reports the other as stale' do
      first_location = create(:inventory_location)
      second_location = create(:inventory_location)
      shared_snapshot = described_class.snapshot_for(inventory)
      ready = Queue.new
      start = Queue.new
      outcomes = Queue.new

      threads = [first_location, second_location].map do |candidate_location|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            result = verify(
              inventory,
              result: :found,
              location_id: candidate_location.id,
              actor: actor,
              snapshot: shared_snapshot
            )
            outcomes << [:success, result.inventory.inventory_location_id]
          rescue StandardError => e
            outcomes << [:error, e]
          end
        end
      end

      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:join)
      results = 2.times.map { outcomes.pop }

      expect(results.count { |type, _value| type == :success }).to eq(1)
      errors = results.filter_map { |type, value| value if type == :error }
      expect(errors.map(&:class)).to contain_exactly(described_class::StaleInventory)
      expect(inventory.reload.inventory_location_id).to be_in([first_location.id, second_location.id])
      expect(InventoryEvent.where(inventory: inventory, event_type: 'physical_inventory_verification').count).to eq(1)
    end
  end
end
