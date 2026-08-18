# frozen_string_literal: true

require 'rails_helper'

# Asignación de ubicación a VARIAS unidades exactas. La garantía que se prueba
# aquí es que "varias" nunca significa "que el sistema elija por mí": cada
# escritura sigue siendo un Inventory ID concreto pasando por el servicio
# canónico, y una unidad en conflicto no arrastra a las demás.
RSpec.describe 'Admin bulk inventory location assignment', type: :request do
  let(:admin) { create(:user, :admin, name: 'Admin Verificador') }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:root_location) { create(:inventory_location) }
  let(:location) { create(:inventory_location, parent: root_location) }

  def unlocated_unit(status: :available)
    create(:inventory, product: product, status: status, inventory_location: nil)
  end

  def snapshot_params(inventories)
    inventories.index_with { |inventory| Inventories::VerifyPhysicalUnitService.snapshot_for(inventory) }
               .transform_keys(&:id)
  end

  describe 'authorization' do
    it 'redirects unauthenticated users to sign in' do
      post bulk_review_admin_inventory_verifications_path, params: { inventory_ids: [1] }

      expect(response).to redirect_to(new_user_session_path)
    end

    %i[customer supplier].each do |role|
      it "denies #{role} users" do
        sign_in create(:user, role: role)

        post bulk_admin_inventory_verifications_path, params: { inventory_ids: [1], location_id: 1 }

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'entry point' do
    it 'sends /admin/inventory/unlocated to a workflow that can assign locations' do
      sign_in admin

      get admin_inventory_unlocated_path

      expect(response).to redirect_to(admin_inventory_verifications_path(q: nil))
    end
  end

  describe 'review step' do
    before { sign_in admin }

    it 'lists exactly the selected units and writes nothing' do
      units = Array.new(3) { unlocated_unit }
      other = unlocated_unit

      expect do
        post bulk_review_admin_inventory_verifications_path, params: { inventory_ids: units.map(&:id) }
      end.not_to change(InventoryEvent, :count)

      expect(response).to have_http_status(:ok)
      units.each { |unit| expect(response.body).to include("bulk-confirm-id-#{unit.id}") }
      expect(response.body).not_to include("bulk-confirm-id-#{other.id}")
      expect(other.reload.inventory_location_id).to be_nil
    end

    it 'refuses an empty selection' do
      post bulk_review_admin_inventory_verifications_path, params: { inventory_ids: [] }

      expect(response).to redirect_to(admin_inventory_verifications_path)
      expect(flash[:alert]).to include('al menos una unidad')
    end

    it 'refuses a batch larger than the per-lot cap before loading anything' do
      oversized = (1..(Admin::InventoryVerificationsController::MAX_BULK_UNITS + 1)).to_a

      post bulk_review_admin_inventory_verifications_path, params: { inventory_ids: oversized }

      expect(response).to redirect_to(admin_inventory_verifications_path)
      expect(flash[:alert]).to include('como máximo')
    end

    it 'drops ids that are not assignable candidates' do
      assignable = unlocated_unit
      already_located = create(:inventory, product: product, status: :available, inventory_location: location)

      post bulk_review_admin_inventory_verifications_path,
           params: { inventory_ids: [assignable.id, already_located.id] }

      expect(response.body).to include("bulk-confirm-id-#{assignable.id}")
      expect(response.body).not_to include("bulk-confirm-id-#{already_located.id}")
    end
  end

  describe 'confirmation step' do
    before { sign_in admin }

    it 'assigns every selected unit through the canonical service and audits each one' do
      units = Array.new(3) { unlocated_unit }

      expect do
        post bulk_admin_inventory_verifications_path, params: {
          inventory_ids: units.map(&:id),
          location_id: location.id,
          expected_snapshots: snapshot_params(units)
        }
      end.to change(InventoryEvent, :count).by(3)

      expect(response).to have_http_status(:ok)
      units.each do |unit|
        expect(unit.reload.inventory_location_id).to eq(location.id)
      end
      expect(InventoryEvent.where(event_type: 'physical_inventory_verification').count).to eq(3)
    end

    it 'leaves unselected inventory untouched' do
      selected = unlocated_unit
      untouched = unlocated_unit

      post bulk_admin_inventory_verifications_path, params: {
        inventory_ids: [selected.id],
        location_id: location.id,
        expected_snapshots: snapshot_params([selected])
      }

      expect(selected.reload.inventory_location_id).to eq(location.id)
      expect(untouched.reload.inventory_location_id).to be_nil
    end

    it 'assigns the healthy units and reports the stale one without touching it' do
      fresh = Array.new(2) { unlocated_unit }
      stale = unlocated_unit
      snapshots = snapshot_params(fresh + [stale])

      # La unidad cambia después de que el admin vio la pantalla de revisión.
      stale.update!(status: :damaged)

      post bulk_admin_inventory_verifications_path, params: {
        inventory_ids: (fresh + [stale]).map(&:id),
        location_id: location.id,
        expected_snapshots: snapshots
      }

      expect(response).to have_http_status(:unprocessable_entity)
      fresh.each { |unit| expect(unit.reload.inventory_location_id).to eq(location.id) }
      expect(stale.reload.inventory_location_id).to be_nil
      expect(response.body).to include("bulk-count-assigned")
    end

    it 'rejects a non-leaf location for every unit without partial writes' do
      units = Array.new(2) { unlocated_unit }
      # Referenciar el hijo obliga a crearlo: sin él la raíz sería hoja y válida.
      parent_with_children = location.parent

      post bulk_admin_inventory_verifications_path, params: {
        inventory_ids: units.map(&:id),
        location_id: parent_with_children.id,
        expected_snapshots: snapshot_params(units)
      }

      expect(response).to have_http_status(:unprocessable_entity)
      units.each { |unit| expect(unit.reload.inventory_location_id).to be_nil }
      expect(InventoryEvent.count).to eq(0)
    end

    it 'never assigns a location that does not exist' do
      unit = unlocated_unit

      post bulk_admin_inventory_verifications_path, params: {
        inventory_ids: [unit.id],
        location_id: 0,
        expected_snapshots: snapshot_params([unit])
      }

      expect(unit.reload.inventory_location_id).to be_nil
    end
  end

  describe 'sellability invariant' do
    before { sign_in admin }

    it 'only becomes customer sellable after the physical location is confirmed' do
      unit = unlocated_unit

      expect(Inventory.customer_sellable).not_to include(unit)

      post bulk_admin_inventory_verifications_path, params: {
        inventory_ids: [unit.id],
        location_id: location.id,
        expected_snapshots: snapshot_params([unit])
      }

      expect(Inventory.customer_sellable).to include(unit.reload)
    end

    it 'keeps a stale unit out of sellable stock' do
      unit = unlocated_unit
      snapshots = snapshot_params([unit])
      unit.update!(status: :damaged)

      post bulk_admin_inventory_verifications_path, params: {
        inventory_ids: [unit.id],
        location_id: location.id,
        expected_snapshots: snapshots
      }

      expect(Inventory.customer_sellable).not_to include(unit.reload)
    end
  end

  # 'pre_reserved' es una pieza que aún viene EN TRÁNSITO y quedó apartada
  # (ReserveSaleOrderItem sólo la marca así cuando inventory.in_transit?).
  # Nadie puede tenerla en la mano, así que aparece en el backlog para que
  # cuadre con el contador del panel, pero no se puede seleccionar ni escribir.
  describe 'pre_reserved units' do
    before { sign_in admin }

    let!(:pre_reserved) do
      create(:inventory, product: product, status: :pre_reserved, inventory_location: nil)
    end

    it 'still appears in the backlog so the count reconciles' do
      get admin_inventory_verifications_path

      expect(response.body).to include("inventory-select-#{pre_reserved.id}")
      expect(response.body).to include('Pre apartado')
    end

    it 'renders its checkbox disabled with an explanation' do
      get admin_inventory_verifications_path

      expect(response.body).to match(
        /id="inventory-select-#{pre_reserved.id}"[^>]*disabled|disabled[^>]*id="inventory-select-#{pre_reserved.id}"/
      )
      expect(response.body).to include("inventory-blocked-#{pre_reserved.id}")
      expect(response.body).to include('sigue en tránsito')
    end

    it 'is counted by the same canonical scope the dashboard counter uses' do
      expect(Inventory.requiring_location.without_location).to include(pre_reserved)
    end

    it 'refuses a forced selection without writing anything' do
      post bulk_admin_inventory_verifications_path, params: {
        inventory_ids: [pre_reserved.id],
        location_id: location.id,
        expected_snapshots: snapshot_params([pre_reserved])
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(pre_reserved.reload.inventory_location_id).to be_nil
      expect(pre_reserved.reload).to be_pre_reserved
      expect(InventoryEvent.count).to eq(0)
    end

    it 'explains itself instead of the generic message on the single-unit page' do
      get admin_inventory_verification_path(pre_reserved)

      expect(response).to redirect_to(admin_inventory_verifications_path)
      expect(flash[:alert]).to include('Pre apartado')
      expect(flash[:alert]).to include('en tránsito')
    end

    it 'never becomes customer sellable through this flow' do
      expect(Inventory.customer_sellable).not_to include(pre_reserved)

      post bulk_admin_inventory_verifications_path, params: {
        inventory_ids: [pre_reserved.id],
        location_id: location.id,
        expected_snapshots: snapshot_params([pre_reserved])
      }

      expect(Inventory.customer_sellable).not_to include(pre_reserved.reload)
    end
  end
end
