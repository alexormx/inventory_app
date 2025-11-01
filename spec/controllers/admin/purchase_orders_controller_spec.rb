# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::PurchaseOrdersController, type: :controller do
  let!(:admin_user) { create(:user, role: 'admin') }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let!(:purchase_order) { create(:purchase_order, user: admin_user, status: 'In Transit') }

  before do
    sign_in admin_user
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

    context 'automatic preorder allocation after receipt' do
      let(:preorder_user) { create(:user, email: 'preorder@test.com') }
      let!(:preorder1) { create(:preorder_reservation, product: product, user: preorder_user, quantity: 1, reserved_at: 2.days.ago) }
      let!(:preorder2) { create(:preorder_reservation, product: product, user: preorder_user, quantity: 1, reserved_at: 1.day.ago) }
      let!(:inventory1) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }
      let!(:inventory2) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }

      it 'automatically assigns received inventory to pending preorders' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        expect(preorder1.reload.status).to eq('assigned')
        expect(preorder2.reload.status).to eq('assigned')
      end

      it 'assigns inventory in FIFO order (oldest preorder first)' do
        # Crear tercera preorder más reciente
        preorder3 = create(:preorder_reservation, product: product, user: preorder_user, quantity: 10, reserved_at: Time.current)

        patch :confirm_receipt, params: { id: purchase_order.id }

        # Solo las 2 primeras preorders deben recibir asignación (2 piezas disponibles)
        expect(preorder1.reload.status).to eq('assigned')
        expect(preorder2.reload.status).to eq('assigned')
        expect(preorder3.reload.status).to eq('pending')
      end

      it 'creates sale order items for assigned preorders' do
        patch :confirm_receipt, params: { id: purchase_order.id }

        preorder_so = preorder1.reload.sale_order
        expect(preorder_so).to be_present
        expect(preorder_so.sale_order_items.where(product: product).exists?).to be true
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
        expect(Rails.logger).to receive(:info).with(/Allocating received inventory to preorders/)

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
      let!(:preorder_p1) { create(:preorder_reservation, product: product, user: preorder_user, quantity: 1) }
      let!(:preorder_p2) { create(:preorder_reservation, product: product2, user: preorder_user, quantity: 1) }
      let!(:inv1) { create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit) }
      let!(:inv2) { create(:inventory, product: product2, purchase_order: purchase_order, status: :in_transit) }

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
