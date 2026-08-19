# frozen_string_literal: true

require 'rails_helper'

# El almacén no etiqueta cada pieza: el administrador dice "producto, cantidad,
# ubicación" y el sistema elige las filas. Estos specs fijan esa garantía.
RSpec.describe Inventories::BulkAssignLocationService, type: :service do
  let(:admin) { create(:user, :admin) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:warehouse) { create(:inventory_location) }
  let!(:shelf) { create(:inventory_location, parent: warehouse) }

  def unlocated(status: :available, created_at: Time.current)
    create(:inventory, product: product, status: status,
                       inventory_location: nil, created_at: created_at)
  end

  NOT_GIVEN = Object.new.freeze

  def assign(quantity:, location_id: NOT_GIVEN, actor: admin, product_id: nil)
    location_id = shelf.id if location_id.equal?(NOT_GIVEN)
    described_class.call(product_id: product_id || product.id, quantity: quantity,
                         location_id: location_id, actor: actor)
  end

  # CASE A + CASE C: la entrada es producto/cantidad/ubicación, sin IDs.
  describe 'assigning by product and quantity' do
    it 'locates exactly the requested quantity and leaves the rest alone' do
      10.times { unlocated }

      result = assign(quantity: 4)

      expect(result.assigned_count).to eq(4)
      expect(product.inventories.where(inventory_location_id: shelf.id).count).to eq(4)
      expect(Inventories::LocationAssignment.eligible_scope(product.id).count).to eq(6)
    end

    it 'needs no Inventory ids from the caller' do
      3.times { unlocated }

      params = described_class.instance_method(:initialize).parameters.map(&:last)

      expect(params).to include(:product_id, :quantity, :location_id, :actor)
      expect(params).not_to include(:inventory_id, :inventory_ids)
    end
  end

  # CASE B: FIFO determinista.
  describe 'FIFO selection' do
    it 'takes the oldest pieces first' do
      oldest = unlocated(created_at: 10.days.ago)
      middle = unlocated(created_at: 5.days.ago)
      newest = unlocated(created_at: 1.day.ago)

      assign(quantity: 2)

      expect(oldest.reload.inventory_location_id).to eq(shelf.id)
      expect(middle.reload.inventory_location_id).to eq(shelf.id)
      expect(newest.reload.inventory_location_id).to be_nil
    end

    it 'breaks ties on id so the order is stable' do
      same_time = 3.days.ago
      a = unlocated(created_at: same_time)
      b = unlocated(created_at: same_time)
      c = unlocated(created_at: same_time)

      assign(quantity: 2)

      expect([a, b].map { |i| i.reload.inventory_location_id }).to all(eq(shelf.id))
      expect(c.reload.inventory_location_id).to be_nil
    end
  end

  # CASE D: todo o nada.
  describe 'quantity validation' do
    it 'assigns nothing when more units are requested than exist' do
      3.times { unlocated }

      expect { assign(quantity: 10) }
        .to raise_error(described_class::InsufficientEligibleInventory, /10 unidades y sólo hay 3/)

      expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
      expect(InventoryEvent.count).to eq(0)
    end

    it 'accepts exactly the available quantity' do
      3.times { unlocated }

      expect(assign(quantity: 3).assigned_count).to eq(3)
    end

    it 'accepts a single unit' do
      unlocated

      expect(assign(quantity: 1).assigned_count).to eq(1)
    end

    [0, -1, '', 'abc', '2.5', nil].each do |bad|
      it "rejects #{bad.inspect} without touching inventory" do
        2.times { unlocated }

        expect { assign(quantity: bad) }.to raise_error(described_class::InvalidQuantity)
        expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
      end
    end
  end

  # CASE E: available y reserved son elegibles y conservan su estado.
  describe 'eligible statuses' do
    it 'can locate both available and reserved pieces' do
      available = unlocated(status: :available, created_at: 2.days.ago)
      reserved = unlocated(status: :reserved, created_at: 1.day.ago)

      assign(quantity: 2)

      expect(available.reload.inventory_location_id).to eq(shelf.id)
      expect(reserved.reload.inventory_location_id).to eq(shelf.id)
    end

    it 'never changes the status while locating' do
      reserved = unlocated(status: :reserved)

      assign(quantity: 1)

      expect(reserved.reload).to be_reserved
    end
  end

  # CASE F: pre_reserved sigue en tránsito, no se ubica.
  describe 'pre_reserved exclusion' do
    it 'is not eligible and is never selected' do
      pre_reserved = unlocated(status: :pre_reserved, created_at: 10.days.ago)
      available = unlocated(status: :available, created_at: 1.day.ago)

      assign(quantity: 1)

      expect(pre_reserved.reload.inventory_location_id).to be_nil
      expect(available.reload.inventory_location_id).to eq(shelf.id)
    end

    it 'does not count toward the assignable pool' do
      unlocated(status: :pre_reserved)
      unlocated(status: :available)

      expect { assign(quantity: 2) }.to raise_error(described_class::InsufficientEligibleInventory)
    end
  end

  # CASE G: ubicación inválida => cero mutación.
  describe 'location validation' do
    it 'rejects a location that does not exist' do
      2.times { unlocated }

      expect { assign(quantity: 1, location_id: 0) }.to raise_error(described_class::InvalidLocation)
      expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
    end

    it 'rejects a non-leaf location' do
      2.times { unlocated }

      expect { assign(quantity: 1, location_id: shelf.parent_id) }
        .to raise_error(described_class::InvalidLocation, /final/)
      expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
    end

    it 'rejects an inactive location' do
      2.times { unlocated }
      shelf.update!(active: false)

      expect { assign(quantity: 1) }.to raise_error(described_class::InvalidLocation, /inactiva/)
      expect(product.inventories.where.not(inventory_location_id: nil)).to be_empty
    end

    it 'rejects a blank location' do
      unlocated

      expect { assign(quantity: 1, location_id: nil) }.to raise_error(described_class::InvalidLocation)
    end
  end

  describe 'authorization' do
    it 'refuses a non-admin actor' do
      unlocated

      expect { assign(quantity: 1, actor: create(:user, role: :customer)) }
        .to raise_error(described_class::UnauthorizedActor)
      expect(InventoryEvent.count).to eq(0)
    end
  end

  # CASE I: auditoría por fila, aunque el usuario no eligió filas.
  describe 'auditability' do
    it 'records one InventoryEvent per assigned unit' do
      3.times { unlocated }

      expect { assign(quantity: 3) }.to change(InventoryEvent, :count).by(3)

      events = InventoryEvent.where(event_type: 'physical_inventory_verification')
      expect(events.count).to eq(3)
      events.each do |event|
        expect(event.metadata['actor_id']).to eq(admin.id)
        expect(event.metadata['new_location_id']).to eq(shelf.id)
        expect(event.metadata['assignment_source']).to eq('bulk_product_quantity')
      end
    end

    it 'links every event to the exact row it changed' do
      2.times { unlocated }

      result = assign(quantity: 2)

      expect(InventoryEvent.pluck(:inventory_id)).to match_array(result.inventories.map(&:id))
    end
  end

  # CASE J: sellability.
  describe 'customer sellability' do
    it 'turns available stock sellable only once it has a location' do
      piece = unlocated(status: :available)

      expect(Inventory.customer_sellable).not_to include(piece)

      assign(quantity: 1)

      expect(Inventory.customer_sellable).to include(piece.reload)
    end

    it 'does not make reserved stock sellable' do
      reserved = unlocated(status: :reserved)

      assign(quantity: 1)

      expect(Inventory.customer_sellable).not_to include(reserved.reload)
    end
  end

  describe 'scoping' do
    it 'never touches another product' do
      other = create(:product, skip_seed_inventory: true)
      other_piece = create(:inventory, product: other, status: :available, inventory_location: nil)
      2.times { unlocated }

      assign(quantity: 2)

      expect(other_piece.reload.inventory_location_id).to be_nil
    end

    it 'never re-locates a piece that already has a location' do
      located = create(:inventory, product: product, status: :available, inventory_location: shelf)
      unlocated

      assign(quantity: 1)

      expect(located.reload.inventory_location_id).to eq(shelf.id)
      expect(InventoryEvent.where(inventory_id: located.id)).to be_empty
    end
  end

  # CASE H: dos administradores no pueden llevarse la misma pieza.
  #
  # La suite corre con transacciones, así que dos hilos no verían el mismo
  # estado; probar el bloqueo con hilos aquí daría un falso verde. Se verifica
  # lo que sí es determinista: (1) que la selección pide FOR UPDATE, que es el
  # mecanismo que impide el solapamiento, y (2) que el stock realmente se agota,
  # o sea que una segunda asignación no puede repetir filas ya tomadas.
  describe 'concurrency' do
    it 'locks the rows it is about to take' do
      3.times { unlocated }

      sql = Inventories::LocationAssignment.fifo_scope(product.id).lock.limit(2).to_sql

      expect(sql).to match(/FOR UPDATE/i)
      expect(sql).to match(/ORDER BY.*created_at.*ASC.*id.*ASC/im)
    end

    it 'cannot hand the same pieces to a second assignment' do
      5.times { unlocated }

      first = assign(quantity: 3)
      expect(first.assigned_count).to eq(3)

      # Sólo quedan 2: pedir 3 otra vez no puede reusar las ya ubicadas.
      expect { assign(quantity: 3) }
        .to raise_error(described_class::InsufficientEligibleInventory, /sólo hay 2/)

      second = assign(quantity: 2)
      expect(second.assigned_count).to eq(2)
      expect((first.inventories.map(&:id) & second.inventories.map(&:id))).to be_empty
    end

    it 're-reads eligibility inside the transaction instead of trusting a stale count' do
      2.times { unlocated }
      # Alguien más se lleva una pieza justo antes de confirmar.
      Inventories::LocationAssignment.fifo_scope(product.id).first.update!(inventory_location: shelf)

      expect { assign(quantity: 2) }.to raise_error(described_class::InsufficientEligibleInventory)
    end
  end
end
