# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SaleOrders::AutoAssignInventoryService do
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:customer) { create(:user) } # role: customer by default

  describe '#call' do
    context 'cuando no hay SOIs pendientes' do
      it 'retorna éxito con 0 asignaciones' do
        result = described_class.new(triggered_by: 'job_scheduled').call

        expect(result.success?).to be true
        expect(result.assigned_count).to eq(0)
        expect(result.pending_count).to eq(0)
      end
    end

    context 'cuando hay SOIs pendientes pero sin inventario disponible' do
      let!(:sale_order) { create(:sale_order, user: customer) }
      let!(:sale_order_item) { create(:sale_order_item, sale_order: sale_order, product: product, quantity: 2) }

      it 'retorna pendientes sin asignar' do
        result = described_class.new(triggered_by: 'job_scheduled').call

        expect(result.success?).to be true
        expect(result.assigned_count).to eq(0)
        expect(result.pending_count).to eq(2) # 2 piezas pendientes
      end
    end

    context 'cuando hay inventario disponible para asignar' do
      let!(:sale_order) { create(:sale_order, user: customer, status: :pending) }
      let!(:sale_order_item) { create(:sale_order_item, sale_order: sale_order, product: product, quantity: 2) }
      let!(:inventory1) { create(:inventory, product: product, status: :available, sale_order: nil) }
      let!(:inventory2) { create(:inventory, product: product, status: :available, sale_order: nil) }

      it 'asigna el inventario a los SOIs' do
        result = described_class.new(triggered_by: 'admin_action').call

        expect(result.success?).to be true
        expect(result.assigned_count).to eq(2)
        expect(result.pending_count).to eq(0)

        # Verificar que el inventario fue asignado
        inventory1.reload
        inventory2.reload
        expect(inventory1.sale_order_id).to eq(sale_order.id)
        expect(inventory2.sale_order_id).to eq(sale_order.id)
        expect(inventory1.sale_order_item_id).to eq(sale_order_item.id)
        expect(inventory2.sale_order_item_id).to eq(sale_order_item.id)
      end

      it 'cambia el estatus del inventario a reserved' do
        described_class.new(triggered_by: 'admin_action').call

        inventory1.reload
        expect(inventory1.status).to eq('reserved')
      end

      it 'crea logs de asignación' do
        expect {
          described_class.new(triggered_by: 'admin_action').call
        }.to change(InventoryAssignmentLog, :count).by_at_least(1)
      end
    end

    context 'con dry_run: true' do
      let!(:sale_order) { create(:sale_order, user: customer, status: :pending) }
      let!(:sale_order_item) { create(:sale_order_item, sale_order: sale_order, product: product, quantity: 1) }
      let!(:inventory) { create(:inventory, product: product, status: :available, sale_order: nil) }

      it 'no modifica el inventario' do
        result = described_class.new(triggered_by: 'admin_action', dry_run: true).call

        expect(result.success?).to be true
        expect(result.assigned_count).to eq(1)

        inventory.reload
        expect(inventory.sale_order_id).to be_nil
        expect(inventory.status).to eq('available')
      end

      it 'no crea logs' do
        expect {
          described_class.new(triggered_by: 'admin_action', dry_run: true).call
        }.not_to change(InventoryAssignmentLog, :count)
      end
    end

    context 'con inventario parcial' do
      let!(:sale_order) { create(:sale_order, user: customer, status: :pending) }
      let!(:sale_order_item) { create(:sale_order_item, sale_order: sale_order, product: product, quantity: 3) }
      let!(:inventory) { create(:inventory, product: product, status: :available, sale_order: nil) }

      it 'asigna lo disponible y reporta pendientes' do
        result = described_class.new(triggered_by: 'admin_action').call

        expect(result.success?).to be true
        expect(result.assigned_count).to eq(1)
        expect(result.pending_count).to eq(2)
      end
    end

    context 'filtrando por sale_order_ids' do
      let!(:sale_order1) { create(:sale_order, user: customer, status: :pending) }
      let!(:sale_order2) { create(:sale_order, user: customer, status: :pending) }
      let!(:soi1) { create(:sale_order_item, sale_order: sale_order1, product: product, quantity: 1) }
      let!(:soi2) { create(:sale_order_item, sale_order: sale_order2, product: product, quantity: 1) }
      let!(:inventory1) { create(:inventory, product: product, status: :available, sale_order: nil) }
      let!(:inventory2) { create(:inventory, product: product, status: :available, sale_order: nil) }

      it 'solo asigna a los SOs especificados' do
        result = described_class.new(
          triggered_by: 'admin_action',
          sale_order_ids: [sale_order1.id]
        ).call

        expect(result.assigned_count).to eq(1)

        inventory1.reload
        inventory2.reload
        # Solo uno debe estar asignado al SO1
        assigned_to_so1 = [inventory1, inventory2].select { |i| i.sale_order_id == sale_order1.id }
        expect(assigned_to_so1.size).to eq(1)
      end
    end

    context 'respetando condiciones de inventario' do
      let!(:sale_order) { create(:sale_order, user: customer, status: :pending) }
      let!(:sale_order_item) do
        create(:sale_order_item,
               sale_order: sale_order,
               product: product,
               quantity: 1,
               item_condition: 'mint')
      end
      let!(:inventory_new) { create(:inventory, product: product, status: :available, sale_order: nil, item_condition: :brand_new) }
      let!(:inventory_mint) { create(:inventory, product: product, status: :available, sale_order: nil, item_condition: :mint) }

      it 'asigna inventario con la condición correcta' do
        result = described_class.new(triggered_by: 'admin_action').call

        expect(result.assigned_count).to eq(1)

        inventory_mint.reload
        expect(inventory_mint.sale_order_id).to eq(sale_order.id)

        inventory_new.reload
        expect(inventory_new.sale_order_id).to be_nil
      end
    end
  end
end
