# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SaleOrders::CancelOrderService, type: :service do
  let(:user) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:sale_order) { create(:sale_order, user: user, status: 'Pending') }

  describe '#call' do
    context 'when sale order has reserved inventories' do
      let!(:inventory1) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }
      let!(:inventory2) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }

      it 'cancels the sale order' do
        service = described_class.new(sale_order)
        service.call

        expect(sale_order.reload.status).to eq('Canceled')
      end

      it 'releases all reserved inventories to available' do
        service = described_class.new(sale_order)
        service.call

        expect(inventory1.reload.status).to eq('available')
        expect(inventory2.reload.status).to eq('available')
      end

      it 'removes sale_order association from inventories' do
        service = described_class.new(sale_order)
        service.call

        expect(inventory1.reload.sale_order_id).to be_nil
        expect(inventory2.reload.sale_order_id).to be_nil
      end

      it 'removes sale_order_item association from inventories' do
        # Crear sale_order_item con quantity=2 para que coincida con los 2 inventories reservados
        sale_order_item = create(:sale_order_item, sale_order: sale_order, product: product, quantity: 2)

        # El callback backfill_inventory_links debería haber asignado sale_order_item_id automáticamente
        # Verificamos que se haya asignado
        expect(inventory1.reload.sale_order_item_id).to eq(sale_order_item.id)
        expect(inventory2.reload.sale_order_item_id).to eq(sale_order_item.id)

        service = described_class.new(sale_order)
        service.call

        # Ambos inventories deberían tener sale_order_item_id limpiado
        expect(inventory1.reload.sale_order_item_id).to be_nil
        expect(inventory2.reload.sale_order_item_id).to be_nil
      end

      it 'updates status_changed_at timestamp' do
        freeze_time do
          service = described_class.new(sale_order)
          service.call

          expect(inventory1.reload.status_changed_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context 'when sale order has sold inventories' do
      let!(:inventory) { create(:inventory, product: product, status: :sold, sale_order: sale_order, sold_price: 123.45) }

      it 'releases sold inventories to available' do
        service = described_class.new(sale_order)
        service.call

        expect(inventory.reload.status).to eq('available')
        expect(inventory.sold_price).to be_nil
      end
    end

    context 'when sale order has pre_reserved inventories' do
      let!(:inventory) { create(:inventory, product: product, status: :pre_reserved, sale_order: sale_order) }

      it 'releases pre_reserved inventories to available' do
        service = described_class.new(sale_order)
        service.call

        expect(inventory.reload.status).to eq('available')
      end
    end

    context 'when sale order has pre_sold inventories' do
      let!(:inventory) { create(:inventory, product: product, status: :pre_sold, sale_order: sale_order) }

      it 'releases pre_sold inventories to available' do
        service = described_class.new(sale_order)
        service.call

        expect(inventory.reload.status).to eq('available')
      end
    end

    context 'when sale order has in_transit inventories' do
      let!(:inventory) { create(:inventory, product: product, status: :in_transit) }

      it 'releases in_transit inventories to available' do
        # Vincular explícitamente al SO a través de una línea para simular asignación en tránsito
        sale_order_item = create(:sale_order_item, sale_order: sale_order, product: product, quantity: 1)
        inventory.update_columns(sale_order_item_id: sale_order_item.id)

        service = described_class.new(sale_order)
        service.call

        expect(inventory.reload.status).to eq('available')
      end
    end

    context 'when sale order is already canceled' do
      let(:canceled_order) { create(:sale_order, user: user, status: 'Canceled') }

      it 'does not change the status' do
        service = described_class.new(canceled_order)
        result = service.call

        expect(result.status).to eq('Canceled')
      end

      it 'returns the sale order without modification' do
        service = described_class.new(canceled_order)
        expect { service.call }.not_to change { canceled_order.updated_at }
      end
    end

    context 'when sale order has no inventories' do
      it 'cancels the order successfully' do
        service = described_class.new(sale_order)
        service.call

        expect(sale_order.reload.status).to eq('Canceled')
      end
    end

    context 'when sale order has inventories in non-releasable states' do
      let!(:damaged_inv) { create(:inventory, product: product, status: :damaged, sale_order: sale_order) }
      let!(:lost_inv) { create(:inventory, product: product, status: :lost, sale_order: sale_order) }

      it 'does not change status of damaged/lost inventories' do
        service = described_class.new(sale_order)
        service.call

        expect(damaged_inv.reload.status).to eq('damaged')
        expect(lost_inv.reload.status).to eq('lost')
      end

      it 'cancels the order' do
        service = described_class.new(sale_order)
        service.call

        expect(sale_order.reload.status).to eq('Canceled')
      end
    end

    context 'product stats update' do
      let!(:inventory1) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }
      let!(:inventory2) { create(:inventory, product: product, status: :sold, sale_order: sale_order) }

      it 'updates product stats after releasing inventories' do
        expect(Products::UpdateStatsService).to receive(:new).with(product).and_call_original

        service = described_class.new(sale_order)
        service.call
      end
    end

    context 'transaction rollback' do
      let!(:inventory) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }

      it 'rolls back if sale order update fails' do
        allow(sale_order).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(sale_order))

        service = described_class.new(sale_order)

        expect { service.call }.to raise_error(ActiveRecord::RecordInvalid)
        expect(inventory.reload.status).to eq('reserved')
        expect(inventory.sale_order_id).to eq(sale_order.id)
      end
    end

    context 'automatic preorder allocation after cancellation' do
      let!(:preorder_user) { create(:user, email: 'preorder@test.com') }
      let!(:preorder1) { create(:preorder_reservation, product: product, user: preorder_user, quantity: 1, reserved_at: 2.days.ago) }
      let!(:preorder2) { create(:preorder_reservation, product: product, user: preorder_user, quantity: 1, reserved_at: 1.day.ago) }

      context 'when releasing inventory from canceled order' do
        let!(:inventory1) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }
        let!(:inventory2) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }

        it 'automatically assigns released inventory to pending preorders in FIFO order' do
          service = described_class.new(sale_order)
          service.call

          # Preorder más antigua (preorder1) debe recibir asignación primero
          expect(preorder1.reload.status).to eq('assigned')
          expect(preorder2.reload.status).to eq('assigned')
        end

        it 'creates sale order items for assigned preorders' do
          service = described_class.new(sale_order)
          service.call

          # Verificar que se crearon sale_order_items
          preorder_so = preorder1.reload.sale_order
          expect(preorder_so).to be_present
          expect(preorder_so.sale_order_items.where(product: product).sum(:quantity)).to be >= 1
        end

        it 'marks inventory as reserved for the preorder sale order' do
          service = described_class.new(sale_order)
          service.call

          # Al menos un inventario debe estar asignado a la orden del preorder
          preorder_so = preorder1.reload.sale_order
          assigned_inventories = Inventory.where(product: product, sale_order: preorder_so, status: :reserved)
          expect(assigned_inventories.count).to be > 0
        end

        it 'respects FIFO order when assigning inventory' do
          # Crear preorder más reciente con más cantidad
          preorder3 = create(:preorder_reservation, product: product, user: preorder_user, quantity: 10, reserved_at: Time.current)

          service = described_class.new(sale_order)
          service.call

          # Solo las primeras 2 preorders (más antiguas) deben recibir asignación con 2 piezas disponibles
          expect(preorder1.reload.status).to eq('assigned')
          expect(preorder2.reload.status).to eq('assigned')
          expect(preorder3.reload.status).to eq('pending') # No hay suficiente inventario para esta
        end

        it 'logs the allocation process' do
          # Permitir todos los logs, pero verificar que se llaman los específicos de allocación
          allow(Rails.logger).to receive(:info).and_call_original

          expect(Rails.logger).to receive(:info).with(/Allocating released inventory/).and_call_original
          expect(Rails.logger).to receive(:info).with(/Preorder allocation completed/).and_call_original

          service = described_class.new(sale_order)
          service.call
        end
      end

      context 'when no pending preorders exist' do
        before do
          PreorderReservation.destroy_all
        end

        let!(:inventory) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }

        it 'does not fail when allocating to empty preorder queue' do
          service = described_class.new(sale_order)
          expect { service.call }.not_to raise_error

          expect(sale_order.reload.status).to eq('Canceled')
          expect(inventory.reload.status).to eq('available')
        end
      end

      context 'when preorder allocation fails' do
        let!(:inventory) { create(:inventory, product: product, status: :reserved, sale_order: sale_order) }

        it 'still cancels the order even if allocation fails' do
          allow(Preorders::PreorderAllocator).to receive(:batch_allocate).and_raise(StandardError.new("Allocation error"))

          service = described_class.new(sale_order)
          expect { service.call }.to raise_error(StandardError, "Allocation error")

          # La orden debe estar cancelada y el inventario liberado (transacción completó antes del allocate)
          expect(sale_order.reload.status).to eq('Canceled')
          expect(inventory.reload.status).to eq('available')
        end
      end
    end
  end
end
