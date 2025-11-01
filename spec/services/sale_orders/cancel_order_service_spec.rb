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
      let!(:inventory) { create(:inventory, product: product, status: :sold, sale_order: sale_order) }

      it 'releases sold inventories to available' do
        service = described_class.new(sale_order)
        service.call

        expect(inventory.reload.status).to eq('available')
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
  end
end
