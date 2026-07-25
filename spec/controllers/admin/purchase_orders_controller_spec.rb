# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::PurchaseOrdersController, type: :controller do
  let!(:admin_user) { create(:user, role: 'admin') }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let!(:purchase_order) { create(:purchase_order, user: admin_user, status: 'In Transit') }

  before do
    # Necesario para Devise en controller specs
    @request.env['devise.mapping'] = Devise.mappings[:user]
    # Evitar dependencias de Warden en controller specs
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:authorize_admin!).and_return(true)
    allow(controller).to receive(:current_user).and_return(admin_user)
  end

  describe 'POST #confirm_receipt' do
    context 'with in_transit inventories' do
      let!(:inventory1) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }
      let!(:inventory2) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }

      it 'marks all in_transit inventories as available' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(inventory1.reload.status).to eq('available')
        expect(inventory2.reload.status).to eq('available')
      end

      it 'updates the purchase order status to Delivered' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(purchase_order.reload.status).to eq('Delivered')
      end

      it 'updates status_changed_at timestamp' do
        freeze_time do
          patch :confirm_receipt, params: { id: purchase_order.id }

          expect(inventory1.reload.status_changed_at).to be_within(1.second).of(Time.current)
          expect(inventory2.reload.status_changed_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'displays success flash message' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(flash[:notice]).to eq('Recepción confirmada. Inventario actualizado.')
      end

      it 'redirects to purchase order show page' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(response).to redirect_to(admin_purchase_order_path(purchase_order))
      end
    end

    context 'with customer-allocated incoming inventory' do
      let(:sale_order) { create(:sale_order) }
      let(:sale_order_item) do
        create(:sale_order_item, sale_order: sale_order, product: product, quantity: 1)
      end

      it 'promotes pre_reserved inventory to reserved when the purchase order is received' do
        inventory = create(
          :inventory,
          product: product,
          purchase_order: purchase_order,
          sale_order: sale_order,
          sale_order_item: sale_order_item,
          status: :pre_reserved
        )

        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(inventory.reload.status).to eq('reserved')
      end

      it 'promotes pre_sold inventory to sold when the purchase order is received' do
        inventory = create(
          :inventory,
          product: product,
          purchase_order: purchase_order,
          sale_order: sale_order,
          sale_order_item: sale_order_item,
          status: :pre_sold
        )

        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(inventory.reload.status).to eq('sold')
      end
    end

    context 'automatic preorder allocation after receipt' do
      let(:preorder_user) { create(:user, email: 'preorder@test.com') }
      let(:location) { create(:inventory_location) }
      let!(:preorder_order1) { create(:sale_order, user: preorder_user) }
      let!(:preorder_order2) { create(:sale_order, user: preorder_user) }
      let!(:preorder_line1) do
        create(:sale_order_item, sale_order: preorder_order1, product: product, quantity: 1, preorder_quantity: 1)
      end
      let!(:preorder_line2) do
        create(:sale_order_item, sale_order: preorder_order2, product: product, quantity: 1, preorder_quantity: 1)
      end
      let!(:preorder1) do
        create(
          :preorder_reservation,
          product: product,
          user: preorder_user,
          sale_order: preorder_order1,
          sale_order_item: preorder_line1,
          quantity: 1,
          reserved_at: 2.days.ago
        )
      end
      let!(:preorder2) do
        create(
          :preorder_reservation,
          product: product,
          user: preorder_user,
          sale_order: preorder_order2,
          sale_order_item: preorder_line2,
          quantity: 1,
          reserved_at: 1.day.ago
        )
      end
      let!(:inventory1) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }
      let!(:inventory2) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }

      before do
        inventory1.update_columns(inventory_location_id: location.id)
        inventory2.update_columns(inventory_location_id: location.id)
      end

      it 'automatically assigns received inventory to pending preorders' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(preorder1.reload.status).to eq('assigned')
        expect(preorder2.reload.status).to eq('assigned')
      end

      it 'assigns inventory in FIFO order (oldest preorder first)' do
        # Crear tercera preorder más reciente
        preorder_order3 = create(:sale_order, user: preorder_user)
        preorder_line3 = create(
          :sale_order_item,
          sale_order: preorder_order3,
          product: product,
          quantity: 10,
          preorder_quantity: 10
        )
        preorder3 = create(
          :preorder_reservation,
          product: product,
          user: preorder_user,
          sale_order: preorder_order3,
          sale_order_item: preorder_line3,
          quantity: 10,
          reserved_at: Time.current
        )

        patch :confirm_receipt, params: { id: purchase_order.id }

        # Solo las 2 primeras preorders deben recibir asignación (2 piezas disponibles)
        expect(preorder1.reload.status).to eq('assigned')
        expect(preorder2.reload.status).to eq('assigned')
        expect(preorder3.reload.status).to eq('pending')
      end

      it 'assigns inventory to the originating sale order items' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(preorder1.reload.sale_order).to eq(preorder_order1)
        expect(preorder1.sale_order_item).to eq(preorder_line1)
        expect(preorder_line1.reload.inventory_units).to contain_exactly(inventory1)
      end

      it 'marks inventory as reserved for preorder sale orders' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        preorder_so1 = preorder1.reload.sale_order
        preorder_so2 = preorder2.reload.sale_order

        # Verificar que al menos un inventario está asignado a cada preorder SO
        expect(Inventory.where(product: product, sale_order: preorder_so1, status: :reserved).count).to be > 0
        expect(Inventory.where(product: product, sale_order: preorder_so2, status: :reserved).count).to be > 0
      end

      it 'logs the allocation process' do
        # Permitir otros logs de Rails y validar que el de asignación aparece
        allow(Rails.logger).to receive(:info).and_call_original
        expect(Rails.logger).to receive(:info).with(/Allocating received inventory to preorders/).and_call_original

        patch :confirm_receipt, params: { id: purchase_order.id }
      end
    end

    context 'when no pending preorders exist' do
      let!(:inventory) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }

      it 'successfully confirms receipt without errors' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(purchase_order.reload.status).to eq('Delivered')
        expect(inventory.reload.status).to eq('available')
        expect(flash[:notice]).to be_present
      end
    end

    context 'when purchase order is not In Transit' do
      let!(:delivered_po) { create(:purchase_order, user: admin_user, status: 'Delivered') }

      it 'does not change inventory status' do
        inventory = create(:inventory, product: product, purchase_order: delivered_po, status: :available)

        patch :confirm_receipt, params: { id: delivered_po.id }

        expect(inventory.reload.status).to eq('available')
      end

      it 'does not change purchase order status' do
        patch :confirm_receipt, params: { id: delivered_po.id }

        expect(delivered_po.reload.status).to eq('Delivered')
      end

      it 'displays error flash message' do
        patch :confirm_receipt, params: { id: delivered_po.id }

        expect(flash[:alert]).to eq("Solo se pueden confirmar órdenes 'In Transit'.")
      end

      it 'redirects to purchase order show page' do
        patch :confirm_receipt, params: { id: delivered_po.id }

        expect(response).to redirect_to(admin_purchase_order_path(delivered_po))
      end
    end

    context 'with multiple products' do
      let(:product2) { create(:product, skip_seed_inventory: true) }
      let(:preorder_user) { create(:user, email: 'preorder@test.com') }
      let(:location) { create(:inventory_location) }
      let!(:preorder_order) { create(:sale_order, user: preorder_user) }
      let!(:preorder_line1) do
        create(:sale_order_item, sale_order: preorder_order, product: product, quantity: 1, preorder_quantity: 1)
      end
      let!(:preorder_line2) do
        create(:sale_order_item, sale_order: preorder_order, product: product2, quantity: 1, preorder_quantity: 1)
      end
      let!(:preorder_p1) do
        create(
          :preorder_reservation,
          product: product,
          user: preorder_user,
          sale_order: preorder_order,
          sale_order_item: preorder_line1,
          quantity: 1
        )
      end
      let!(:preorder_p2) do
        create(
          :preorder_reservation,
          product: product2,
          user: preorder_user,
          sale_order: preorder_order,
          sale_order_item: preorder_line2,
          quantity: 1
        )
      end
      let!(:inv1) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }
      let!(:inv2) { create(:inventory, product: product2, purchase_order: purchase_order, status: :in_transit) }

      before do
        inv1.update_columns(inventory_location_id: location.id)
        inv2.update_columns(inventory_location_id: location.id)
      end

      it 'allocates each product to its respective preorders' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(preorder_p1.reload.status).to eq('assigned')
        expect(preorder_p2.reload.status).to eq('assigned')
      end

      it 'calls batch_allocate with all product IDs' do
        expect(Preorders::PreorderAllocator).to receive(:batch_allocate).with(array_including(product.id, product2.id))

        patch :confirm_receipt, params: { id: purchase_order.id }
      end
    end

    context 'when allocation fails' do
      let!(:inventory) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }

      it 'still marks inventory as available even if allocation fails' do
        allow(Preorders::PreorderAllocator).to receive(:batch_allocate).and_raise(StandardError.new("Allocation failed"))

        expect { patch :confirm_receipt, params: { id: purchase_order.id } }.to raise_error(StandardError)

        # El inventory debe estar disponible (update_all se ejecutó antes del allocate)
        expect(inventory.reload.status).to eq('available')
        expect(purchase_order.reload.status).to eq('Delivered')
      end
    end
  end
end
