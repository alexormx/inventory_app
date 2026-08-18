# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin physical inventory verifications', type: :request do
  let(:admin) { create(:user, :admin, name: 'Admin Verificador') }
  let(:service) { Inventories::VerifyPhysicalUnitService }

  def verification_payload(inventory, result:, location_id: nil, snapshot: nil, notes: nil)
    {
      verification: {
        inventory_id: inventory.id,
        result: result,
        location_id: location_id,
        notes: notes,
        expected_snapshot: snapshot || Inventories::VerifyPhysicalUnitService.snapshot_for(inventory)
      }
    }
  end

  describe 'authorization' do
    it 'redirects unauthenticated users to sign in' do
      get admin_inventory_verifications_path

      expect(response).to redirect_to(new_user_session_path)
    end

    %i[customer supplier].each do |role|
      it "denies #{role} users" do
        sign_in create(:user, role: role)

        get admin_inventory_verifications_path

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Acceso denegado')
      end
    end

    it 'allows admins to open the workflow' do
      sign_in admin

      get admin_inventory_verifications_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Verificación física')
    end

    it 'does not allow a non-admin to mutate inventory' do
      inventory = create(:inventory, inventory_location: nil)
      location = create(:inventory_location, :warehouse)
      payload = verification_payload(inventory, result: 'found', location_id: location.id)
      sign_in create(:user)

      expect do
        post admin_inventory_verifications_path, params: payload
      end.not_to change(InventoryEvent, :count)

      expect(response).to redirect_to(root_path)
      expect(inventory.reload.inventory_location_id).to be_nil
    end
  end

  describe 'GET /admin/inventory_verifications' do
    before { sign_in admin }

    it 'finds one exact eligible Inventory ID' do
      match = create(:inventory, inventory_location: nil)
      other = create(:inventory, inventory_location: nil)

      get admin_inventory_verifications_path, params: { search_by: 'inventory_id', q: match.id }

      expect(response.body).to include("data-inventory-id=\"#{match.id}\"")
      expect(response.body).not_to include("data-inventory-id=\"#{other.id}\"")
    end

    it 'searches candidate units by product SKU' do
      product = create(:product, skip_seed_inventory: true, product_sku: 'PHY-SKU-105')
      inventory = create(:inventory, product: product, inventory_location: nil)

      get admin_inventory_verifications_path, params: { search_by: 'sku', q: 'sku-105' }

      expect(response.body).to include("data-inventory-id=\"#{inventory.id}\"")
    end

    it 'searches candidate units by product name' do
      product = create(:product, skip_seed_inventory: true, product_name: 'Celica verificación especial')
      inventory = create(:inventory, product: product, inventory_location: nil)

      get admin_inventory_verifications_path, params: { search_by: 'product_name', q: 'VERIFICACIÓN' }

      expect(response.body).to include("data-inventory-id=\"#{inventory.id}\"")
    end

    it 'treats wildcard characters literally in product-name searches' do
      matching_product = create(:product, skip_seed_inventory: true, product_name: "Limited Edition '_100% Model")
      other_product = create(:product, skip_seed_inventory: true, product_name: 'Limited Edition X100Y Model')
      matching_inventory = create(:inventory, product: matching_product, inventory_location: nil)
      other_inventory = create(:inventory, product: other_product, inventory_location: nil)

      get admin_inventory_verifications_path, params: { search_by: 'product_name', q: "EDITION '_100%" }

      expect(response.body).to include("data-inventory-id=\"#{matching_inventory.id}\"")
      expect(response.body).not_to include("data-inventory-id=\"#{other_inventory.id}\"")
    end

    it 'searches by PurchaseOrder and PurchaseOrderItem identifiers' do
      product = create(:product, skip_seed_inventory: true)
      purchase_order = create(:purchase_order)
      purchase_order_item = create(:purchase_order_item, purchase_order: purchase_order, product: product)
      inventory = create(
        :inventory,
        product: product,
        purchase_order: purchase_order,
        purchase_order_item: purchase_order_item,
        inventory_location: nil
      )

      get admin_inventory_verifications_path, params: { search_by: 'purchase_order', q: purchase_order.id }
      expect(response.body).to include("data-inventory-id=\"#{inventory.id}\"")

      get admin_inventory_verifications_path, params: { search_by: 'purchase_order_item', q: purchase_order_item.id }
      expect(response.body).to include("data-inventory-id=\"#{inventory.id}\"")
    end

    it 'searches reserved units by SaleOrder and SaleOrderItem identifiers' do
      product = create(:product, skip_seed_inventory: true)
      sale_order = create(:sale_order)
      sale_order_item = create(:sale_order_item, sale_order: sale_order, product: product)
      inventory = create(
        :inventory,
        product: product,
        status: :reserved,
        sale_order: sale_order,
        sale_order_item: sale_order_item,
        inventory_location: nil
      )

      get admin_inventory_verifications_path, params: { search_by: 'sale_order', q: sale_order.id }
      expect(response.body).to include("data-inventory-id=\"#{inventory.id}\"")

      get admin_inventory_verifications_path, params: { search_by: 'sale_order_item', q: sale_order_item.id }
      expect(response.body).to include("data-inventory-id=\"#{inventory.id}\"")
    end

    # El backlog lista lo mismo que cuenta el panel (Inventory.requiring_location
    # sin ubicación). Lo que decide si una pieza se puede verificar es su estado,
    # no si aparece: 'pre_reserved' sale listada pero con la casilla deshabilitada,
    # porque sigue en tránsito y nadie puede tenerla en la mano.
    it 'displays every unlocated unit that requires a location' do
      available = create(:inventory, status: :available, inventory_location: nil)
      reserved = create(:inventory, status: :reserved, inventory_location: nil)
      located = create(:inventory, status: :available, inventory_location: create(:inventory_location))
      pre_reserved = create(:inventory, status: :pre_reserved, inventory_location: nil)
      sold = create(:inventory, status: :sold, inventory_location: nil)

      get admin_inventory_verifications_path

      expect(response.body).to include("data-inventory-id=\"#{available.id}\"")
      expect(response.body).to include("data-inventory-id=\"#{reserved.id}\"")
      expect(response.body).to include("data-inventory-id=\"#{pre_reserved.id}\"")
      expect(response.body).not_to include("data-inventory-id=\"#{located.id}\"")
      expect(response.body).not_to include("data-inventory-id=\"#{sold.id}\"")
    end

    it 'only offers a usable checkbox for units that can be physically verified' do
      available = create(:inventory, status: :available, inventory_location: nil)
      pre_reserved = create(:inventory, status: :pre_reserved, inventory_location: nil)

      get admin_inventory_verifications_path

      expect(response.body).to match(
        /id="inventory-select-#{available.id}"(?![^>]*disabled)/
      )
      expect(response.body).to match(
        /id="inventory-select-#{pre_reserved.id}"[^>]*disabled|disabled[^>]*id="inventory-select-#{pre_reserved.id}"/
      )
    end

    it 'paginates broad result sets' do
      create_list(:inventory, 21, inventory_location: nil)

      get admin_inventory_verifications_path

      expect(response.body.scan('data-inventory-id=').size).to eq(20)
      expect(response.body).to include('page=2')
    end
  end

  describe 'GET /admin/inventory_verifications/:id' do
    before { sign_in admin }

    it 'loads an exact candidate with the canonical six-field snapshot' do
      inventory = create(:inventory, status: :available, inventory_location: nil)
      canonical_time = Time.utc(2026, 8, 12, 4, 5, 6, 123_456)
      inventory.update_column(:updated_at, canonical_time)
      inventory.reload

      get admin_inventory_verification_path(inventory)

      document = Nokogiri::HTML(response.body)
      service::SNAPSHOT_FIELDS.each do |field|
        input = document.at_css("input[name='verification[expected_snapshot][#{field}]']")
        expect(input).to be_present
      end
      expect(document.at_css("input[name='verification[expected_snapshot][updated_at]']")['value'])
        .to eq('2026-08-12T04:05:06.123456Z')

      found_form = document.at_css('[data-verification-result="found"] form')
      found_submit = found_form.at_css('input[type="submit"]')
      expect(found_form['data-turbo']).not_to eq('false')
      expect(found_submit['data-turbo-confirm']).to include("Inventory ##{inventory.id}")
      expect(found_submit['data-turbo-submits-with']).to eq('Verificando…')
    end

    it 'only offers active final leaf locations' do
      inventory = create(:inventory, inventory_location: nil)
      parent = create(:inventory_location, :warehouse, name: 'Bodega Padre')
      leaf = create(:inventory_location, :bin, parent: parent, name: 'Contenedor Final')
      inactive = create(:inventory_location, :inactive, name: 'Ubicación Inactiva')

      get admin_inventory_verification_path(inventory)

      document = Nokogiri::HTML(response.body)
      option_values = document.css('select[name="verification[location_id]"] option').pluck('value')
      expect(option_values).to include(leaf.id.to_s)
      expect(option_values).not_to include(parent.id.to_s, inactive.id.to_s)
    end

    it 'does not offer a located unit' do
      inventory = create(:inventory, status: :available, inventory_location: create(:inventory_location))

      get admin_inventory_verification_path(inventory)

      expect(response).to redirect_to(admin_inventory_verifications_path)
    end

    it 'does not offer an unsupported status' do
      inventory = create(:inventory, status: :pre_reserved, inventory_location: nil)

      get admin_inventory_verification_path(inventory)

      expect(response).to redirect_to(admin_inventory_verifications_path)
    end

    it 'offers only Found for reserved inventory and explains reconciliation' do
      inventory = create(:inventory, status: :reserved, inventory_location: nil)

      get admin_inventory_verification_path(inventory)

      document = Nokogiri::HTML(response.body)
      expect(document.css('input[name="verification[result]"]').pluck('value').uniq).to eq(['found'])
      expect(response.body).to include('requiere conciliación a nivel de orden')
    end
  end

  describe 'POST /admin/inventory_verifications' do
    before { sign_in admin }

    it 'verifies an exact available unit as found and displays its audit event' do
      inventory = create(:inventory, status: :available, inventory_location: nil)
      location = create(:inventory_location, :warehouse, name: 'Anaquel Encontrado')

      expect do
        post admin_inventory_verifications_path,
             params: verification_payload(inventory, result: 'found', location_id: location.id, notes: 'Conteo físico')
      end.to change(InventoryEvent, :count).by(1)

      event = InventoryEvent.last
      expect(response).to redirect_to(admin_inventory_verification_path(inventory, event_id: event.id))
      expect(inventory.reload).to be_available
      expect(inventory.inventory_location).to eq(location)
      expect(event.event_type).to eq('physical_inventory_verification')
      expect(event.metadata['actor_id']).to eq(admin.id)

      follow_redirect!
      expect(response.body).to include('Verificación registrada', 'Conteo físico', 'Admin Verificador')
    end

    it 'keeps the event location historically accurate after the Inventory moves' do
      inventory = create(:inventory, status: :available, inventory_location: nil)
      verified_location = create(:inventory_location, :warehouse, name: 'Ubicación Histórica A')
      later_location = create(:inventory_location, :warehouse, name: 'Ubicación Actual B')

      post admin_inventory_verifications_path,
           params: verification_payload(inventory, result: 'found', location_id: verified_location.id)
      event = InventoryEvent.where(event_type: 'physical_inventory_verification').order(:id).last!
      inventory.update!(inventory_location: later_location)

      get admin_inventory_verification_path(inventory, event_id: event.id)

      historical_location = Nokogiri::HTML(response.body).at_css('#verification-new-location')
      expect(historical_location['data-location-id']).to eq(verified_location.id.to_s)
      expect(historical_location.text).to include('Ubicación Histórica A', "Ubicación ##{verified_location.id}")
      expect(historical_location.text).not_to include('Ubicación Actual B')
    end

    it 'shows the stored historical location ID when that location no longer exists' do
      inventory = create(:inventory, status: :available, inventory_location: nil)
      verified_location = create(:inventory_location, :warehouse)
      later_location = create(:inventory_location, :warehouse)

      post admin_inventory_verifications_path,
           params: verification_payload(inventory, result: 'found', location_id: verified_location.id)
      event = InventoryEvent.where(event_type: 'physical_inventory_verification').order(:id).last!
      historical_location_id = verified_location.id
      inventory.update!(inventory_location: later_location)
      verified_location.destroy!

      get admin_inventory_verification_path(inventory, event_id: event.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Ubicación ##{historical_location_id} (ya no disponible)")
    end

    it 'verifies a reserved unit as found while preserving its order links' do
      product = create(:product, skip_seed_inventory: true)
      sale_order = create(:sale_order)
      sale_order_item = create(:sale_order_item, sale_order: sale_order, product: product)
      inventory = create(
        :inventory,
        product: product,
        status: :reserved,
        sale_order: sale_order,
        sale_order_item: sale_order_item,
        inventory_location: nil
      )
      location = create(:inventory_location)

      post admin_inventory_verifications_path,
           params: verification_payload(inventory, result: 'found', location_id: location.id)

      inventory.reload
      expect(response).to have_http_status(:see_other)
      expect(inventory).to be_reserved
      expect(inventory.sale_order).to eq(sale_order)
      expect(inventory.sale_order_item).to eq(sale_order_item)
      expect(inventory.inventory_location).to eq(location)
    end

    it 'changes available inventory to damaged without a location' do
      inventory = create(:inventory, status: :available, inventory_location: nil)

      post admin_inventory_verifications_path,
           params: verification_payload(inventory, result: 'damaged')

      expect(response).to have_http_status(:see_other)
      expect(inventory.reload).to be_damaged
      expect(inventory.inventory_location_id).to be_nil
    end

    it 'changes available inventory to lost when it is missing' do
      inventory = create(:inventory, status: :available, inventory_location: nil)

      post admin_inventory_verifications_path,
           params: verification_payload(inventory, result: 'missing')

      expect(response).to have_http_status(:see_other)
      expect(inventory.reload).to be_lost
      expect(inventory.inventory_location_id).to be_nil
    end

    %w[damaged missing].each do |result|
      it "rejects #{result} for reserved inventory without mutation" do
        inventory = create(:inventory, status: :reserved, inventory_location: nil)

        expect do
          post admin_inventory_verifications_path,
               params: verification_payload(inventory, result: result)
        end.not_to change(InventoryEvent, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('requiere conciliación a nivel de orden')
        expect(inventory.reload).to be_reserved
      end
    end

    it 'returns conflict for a stale canonical snapshot without overwriting' do
      inventory = create(:inventory, status: :available, inventory_location: nil)
      stale_snapshot = service.snapshot_for(inventory)
      inventory.touch

      expect do
        post admin_inventory_verifications_path,
             params: verification_payload(inventory, result: 'missing', snapshot: stale_snapshot)
      end.not_to change(InventoryEvent, :count)

      expect(response).to have_http_status(:conflict)
      expect(response.body).to include('El inventario cambió', 'Fecha de actualización')
      expect(inventory.reload).to be_available
    end

    it 'returns 422 for an inactive location without mutating inventory' do
      inventory = create(:inventory, status: :available, inventory_location: nil)
      inactive_location = create(:inventory_location, :inactive)

      expect do
        post admin_inventory_verifications_path,
             params: verification_payload(inventory, result: 'found', location_id: inactive_location.id)
      end.not_to change(InventoryEvent, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('La ubicación no es válida')
      expect(inventory.reload.inventory_location_id).to be_nil
    end

    it 'returns 422 for an invalid snapshot' do
      inventory = create(:inventory, status: :available, inventory_location: nil)
      invalid_snapshot = service.snapshot_for(inventory).except(:updated_at)

      post admin_inventory_verifications_path,
           params: verification_payload(inventory, result: 'missing', snapshot: invalid_snapshot)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('No fue posible validar el estado cargado')
      expect(inventory.reload).to be_available
    end

    it 'returns 422 for an unsupported verification result' do
      inventory = create(:inventory, status: :available, inventory_location: nil)

      expect do
        post admin_inventory_verifications_path,
             params: verification_payload(inventory, result: 'sold')
      end.not_to change(InventoryEvent, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('resultado de verificación permitido')
      expect(inventory.reload).to be_available
    end

    it 'returns 422 when the unit is no longer eligible' do
      inventory = create(:inventory, status: :sold, inventory_location: nil)

      post admin_inventory_verifications_path,
           params: verification_payload(inventory, result: 'missing')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('ya no es elegible')
      expect(inventory.reload).to be_sold
    end
  end
end
