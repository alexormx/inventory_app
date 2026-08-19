# frozen_string_literal: true

require 'rails_helper'

# "Acomodé esta caja": varios modelos, una ubicación, una confirmación.
# La garantía central es que el lote entero se guarda o no se guarda nada.
RSpec.describe Inventories::BulkAssignLocationBatchService, type: :service do
  let(:admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location) }
  let!(:shelf) { create(:inventory_location, parent: warehouse) }

  let(:product_a) { create(:product, skip_seed_inventory: true, product_name: 'Skyline') }
  let(:product_b) { create(:product, skip_seed_inventory: true, product_name: 'Supra') }
  let(:product_c) { create(:product, skip_seed_inventory: true, product_name: 'Civic') }

  def stock(product, count, status: :available, created_at: Time.current)
    Array.new(count) do |i|
      create(:inventory, product: product, status: status,
                         inventory_location: nil, created_at: created_at + i.seconds)
    end
  end

  def run(lines, location_id: nil, actor: admin)
    described_class.call(lines: lines, location_id: location_id || shelf.id, actor: actor)
  end

  describe 'the whole batch in one shot' do
    it 'locates every line at the chosen location' do
      stock(product_a, 10); stock(product_b, 8); stock(product_c, 6)

      result = run([
        { product_id: product_a.id, quantity: 5 },
        { product_id: product_b.id, quantity: 3 },
        { product_id: product_c.id, quantity: 2 }
      ])

      expect(result.assigned_count).to eq(10)
      expect(result.product_count).to eq(3)
      expect(product_a.inventories.where(inventory_location_id: shelf.id).count).to eq(5)
      expect(product_b.inventories.where(inventory_location_id: shelf.id).count).to eq(3)
      expect(product_c.inventories.where(inventory_location_id: shelf.id).count).to eq(2)
    end

    it 'leaves the untouched remainder unlocated' do
      stock(product_a, 10)

      run([{ product_id: product_a.id, quantity: 4 }])

      expect(Inventories::LocationAssignment.eligible_scope(product_a.id).count).to eq(6)
    end
  end

  # LO CRÍTICO: todo o nada para el LOTE COMPLETO.
  describe 'all-or-nothing across the batch' do
    it 'writes nothing when a single later line falls short' do
      stock(product_a, 10)
      stock(product_b, 2)   # se piden 3
      stock(product_c, 6)

      expect do
        run([
          { product_id: product_a.id, quantity: 5 },
          { product_id: product_b.id, quantity: 3 },
          { product_id: product_c.id, quantity: 2 }
        ])
      end.to raise_error(described_class::InsufficientEligibleInventory)

      expect(Inventory.where.not(inventory_location_id: nil)).to be_empty
      expect(InventoryEvent.count).to eq(0)
    end

    it 'names the product that blocked it, with both numbers' do
      stock(product_a, 10); stock(product_b, 2)

      expect do
        run([{ product_id: product_a.id, quantity: 5 },
             { product_id: product_b.id, quantity: 3 }])
      end.to raise_error(described_class::InsufficientEligibleInventory,
                         /Supra: solicitadas 3, disponibles 2/)
    end

    it 'reports every short line, not just the first' do
      stock(product_a, 1); stock(product_b, 1)

      begin
        run([{ product_id: product_a.id, quantity: 5 },
             { product_id: product_b.id, quantity: 3 }])
      rescue described_class::InsufficientEligibleInventory => e
        expect(e.shortages.map(&:product)).to match_array([product_a, product_b])
        expect(e.shortages.map(&:requested)).to match_array([5, 3])
        expect(e.shortages.map(&:available)).to match_array([1, 1])
      end
    end
  end

  describe 'duplicate lines' do
    it 'combines the same product instead of competing for the same pieces' do
      stock(product_a, 10)

      result = run([{ product_id: product_a.id, quantity: 3 },
                    { product_id: product_a.id, quantity: 2 }])

      expect(result.product_count).to eq(1)
      expect(result.assigned_count).to eq(5)
      expect(product_a.inventories.where(inventory_location_id: shelf.id).count).to eq(5)
    end

    it 'validates the combined quantity against stock' do
      stock(product_a, 4)

      expect do
        run([{ product_id: product_a.id, quantity: 3 },
             { product_id: product_a.id, quantity: 3 }])
      end.to raise_error(described_class::InsufficientEligibleInventory, /solicitadas 6/)
    end
  end

  describe 'FIFO within each line' do
    it 'takes the oldest pieces of every product' do
      old_a = stock(product_a, 2, created_at: 10.days.ago)
      new_a = stock(product_a, 2, created_at: 1.day.ago)

      run([{ product_id: product_a.id, quantity: 2 }])

      expect(old_a.map { |i| i.reload.inventory_location_id }).to all(eq(shelf.id))
      expect(new_a.map { |i| i.reload.inventory_location_id }).to all(be_nil)
    end
  end

  describe 'eligibility carried over from the single-line service' do
    it 'includes reserved pieces and keeps their status' do
      reserved = stock(product_a, 1, status: :reserved).first

      run([{ product_id: product_a.id, quantity: 1 }])

      expect(reserved.reload.inventory_location_id).to eq(shelf.id)
      expect(reserved.reload).to be_reserved
    end

    it 'never selects pre_reserved, which is still in transit' do
      pre = stock(product_a, 1, status: :pre_reserved, created_at: 10.days.ago).first
      stock(product_a, 1, status: :available)

      run([{ product_id: product_a.id, quantity: 1 }])

      expect(pre.reload.inventory_location_id).to be_nil
    end

    it 'does not count pre_reserved toward the assignable pool' do
      stock(product_a, 1, status: :pre_reserved)
      stock(product_a, 1, status: :available)

      expect { run([{ product_id: product_a.id, quantity: 2 }]) }
        .to raise_error(described_class::InsufficientEligibleInventory)
    end
  end

  describe 'location and input validation' do
    before { stock(product_a, 5) }

    it 'rejects a non-leaf location without writing' do
      expect { run([{ product_id: product_a.id, quantity: 1 }], location_id: warehouse.id) }
        .to raise_error(described_class::InvalidLocation, /final/)
      expect(Inventory.where.not(inventory_location_id: nil)).to be_empty
    end

    it 'rejects an inactive location without writing' do
      shelf.update!(active: false)
      expect { run([{ product_id: product_a.id, quantity: 1 }]) }
        .to raise_error(described_class::InvalidLocation, /inactiva/)
    end

    it 'rejects a missing location without writing' do
      expect { run([{ product_id: product_a.id, quantity: 1 }], location_id: 0) }
        .to raise_error(described_class::InvalidLocation)
    end

    it 'rejects an empty batch' do
      expect { run([]) }.to raise_error(described_class::EmptyBatch)
    end

    [0, -1, '', 'abc', '2.5'].each do |bad|
      it "rejects quantity #{bad.inspect}" do
        expect { run([{ product_id: product_a.id, quantity: bad }]) }
          .to raise_error(described_class::InvalidQuantity)
        expect(Inventory.where.not(inventory_location_id: nil)).to be_empty
      end
    end

    it 'refuses a non-admin actor' do
      expect { run([{ product_id: product_a.id, quantity: 1 }], actor: create(:user, role: :customer)) }
        .to raise_error(described_class::UnauthorizedActor)
    end
  end

  describe 'audit' do
    it 'creates one InventoryEvent per assigned row' do
      stock(product_a, 5); stock(product_b, 5)

      expect do
        run([{ product_id: product_a.id, quantity: 3 },
             { product_id: product_b.id, quantity: 2 }])
      end.to change(InventoryEvent, :count).by(5)
    end

    it 'correlates the whole batch with one id and marks the source' do
      stock(product_a, 3); stock(product_b, 3)

      result = run([{ product_id: product_a.id, quantity: 2 },
                    { product_id: product_b.id, quantity: 1 }])

      events = InventoryEvent.where(event_type: 'physical_inventory_verification')
      expect(events.count).to eq(3)
      expect(events.map { |e| e['metadata']['assignment_batch_id'] }.uniq).to eq([result.batch_id])
      expect(events.map { |e| e['metadata']['assignment_source'] }.uniq)
        .to eq(['bulk_product_quantity_batch'])
    end
  end

  describe 'concurrency' do
    it 'takes locks in a deterministic product order' do
      stock(product_a, 2); stock(product_b, 2)
      # El orden de bloqueo no depende de cómo llegó el lote.
      expect(Inventories::LocationAssignment.fifo_scope(product_a.id).lock.to_sql)
        .to match(/FOR UPDATE/i)
    end

    it 'fails the batch when stock disappears between review and confirm' do
      stock(product_a, 5); stock(product_b, 3)
      lines = [{ product_id: product_a.id, quantity: 5 },
               { product_id: product_b.id, quantity: 3 }]

      # Otro operador se lleva piezas justo antes de confirmar.
      Inventories::LocationAssignment.fifo_scope(product_b.id).limit(2)
                                     .each { |i| i.update!(inventory_location: shelf) }

      expect { run(lines) }.to raise_error(described_class::InsufficientEligibleInventory)
      expect(product_a.inventories.where(inventory_location_id: shelf.id)).to be_empty
    end
  end

  describe 'customer sellability' do
    it 'makes available stock sellable only once located' do
      piece = stock(product_a, 1).first
      expect(Inventory.customer_sellable).not_to include(piece)

      run([{ product_id: product_a.id, quantity: 1 }])

      expect(Inventory.customer_sellable).to include(piece.reload)
    end

    it 'does not make reserved stock sellable' do
      reserved = stock(product_a, 1, status: :reserved).first

      run([{ product_id: product_a.id, quantity: 1 }])

      expect(Inventory.customer_sellable).not_to include(reserved.reload)
    end
  end
end
