# frozen_string_literal: true

require 'rails_helper'

# Reducir la cantidad de una Purchase Order retira suministro entrante que aún
# no está comprometido. Tres cosas tienen que ser ciertas a la vez:
#
#   * una reducción legítima sobre unidades LIBRES debe completarse;
#   * una reducción que tocaría unidades COMPROMETIDAS debe seguir bloqueada;
#   * el historial de InventoryEvent debe sobrevivir intacto.
#
# La pieza retirada no se destruye: se lleva a :scrap, el mismo ciclo de vida
# que la aplicación ya usa cuando se cancela una PO completa.
RSpec.describe 'Purchase order quantity reduction', type: :model do
  let(:product) { create(:product, skip_seed_inventory: true, status: 'active') }
  let(:purchase_order) { create(:purchase_order, status: 'In Transit') }

  def line_with(quantity)
    create(:purchase_order_item, purchase_order: purchase_order, product: product, quantity: quantity)
  end

  def units_for(item)
    Inventory.where(purchase_order_item_id: item.id).order(:id)
  end

  # Historial de auditoría real: el mismo tipo de evento que deja el recálculo
  # de costos, que en producción toca casi toda pieza.
  def audit!(inventory, event_type: 'status_change')
    InventoryEvent.create!(
      inventory: inventory,
      product: product,
      event_type: event_type,
      metadata: { note: 'audit trail' }
    )
  end

  def committed_sale_line(quantity)
    sale_order = create(:sale_order)
    line = create(
      :sale_order_item,
      sale_order: sale_order, product: product, quantity: quantity,
      unit_cost: 40, unit_selling_price: 100, unit_final_price: 100,
      total_line_cost: 100 * quantity
    )
    [sale_order, line]
  end

  describe 'when the freed units carry audit history' do
    it 'completes the reduction and preserves every audit event' do
      item = line_with(4)
      units = units_for(item).to_a
      expect(units.size).to eq(4)

      units.each { |unit| audit!(unit) }
      all_ids = units.map(&:id)

      expect(item.send(:free_inventory_scope).count).to eq(4)
      expect { item.update!(quantity: 2) }.not_to raise_error

      aggregate_failures do
        expect(item.reload.quantity).to eq(2)
        # Ninguna fila desapareció y ningún evento previo se perdió.
        expect(Inventory.where(id: all_ids).count).to eq(4)
        expect(
          InventoryEvent.where(inventory_id: all_ids, event_type: 'status_change')
                        .where("metadata::text LIKE '%audit trail%'").count
        ).to eq(4)
        # El retiro añade su propio rastro, sin tocar el anterior.
        expect(
          InventoryEvent.where(inventory_id: all_ids)
                        .where("metadata::text LIKE '%purchase_order_quantity_reduced%'").count
        ).to eq(2)
      end
    end

    it 'retires the excess units to scrap instead of destroying them' do
      item = line_with(4)
      units_for(item).each { |unit| audit!(unit) }

      item.update!(quantity: 1)

      aggregate_failures do
        expect(Inventory.customer_in_transit.where(product: product).count).to eq(1)
        expect(units_for(item).where(status: :in_transit).count).to eq(1)
        expect(units_for(item).where(status: :scrap).count).to eq(3)
        expect(units_for(item).count).to eq(4)
      end
    end

    it 'records why each unit was retired, with purchase order traceability' do
      item = line_with(3)
      item.update!(quantity: 1)

      retired = units_for(item).where(status: :scrap)
      expect(retired.count).to eq(2)

      events = InventoryEvent.where(inventory_id: retired.select(:id), event_type: 'status_change')
      expect(events.count).to eq(2)

      events.each do |event|
        expect(event.metadata['reason']).to eq('purchase_order_quantity_reduced')
        expect(event.metadata['previous_status']).to eq('in_transit')
        expect(event.metadata['new_status']).to eq('scrap')
        expect(event.metadata['purchase_order_id']).to eq(purchase_order.id)
        expect(event.metadata['purchase_order_item_id']).to eq(item.id)
      end
    end

    it 'keeps retired units out of customer-facing stock' do
      item = line_with(3)
      item.update!(quantity: 1)

      aggregate_failures do
        expect(Inventory.customer_sellable.where(product: product).count).to eq(1)
        expect(Inventory.customer_on_hand.where(product: product).count).to eq(0)
        expect(Inventory.free.where(product: product).count).to eq(1)
      end
    end

    it 'does not double-count retired units on a later quantity change' do
      item = line_with(4)
      item.update!(quantity: 2)
      expect(units_for(item).where(status: :scrap).count).to eq(2)

      # Volver a subir debe crear piezas nuevas, no resucitar las retiradas.
      item.update!(quantity: 3)

      aggregate_failures do
        expect(units_for(item).where.not(status: :scrap).count).to eq(3)
        expect(units_for(item).where(status: :scrap).count).to eq(2)
        expect(units_for(item).count).to eq(5)
      end
    end
  end

  describe 'guards over committed inventory (must not weaken)' do
    {
      pre_reserved: 8,
      reserved: 1,
      pre_sold: 9,
      sold: 3
    }.each do |status_name, status_value|
      it "blocks the reduction when the units are #{status_name}" do
        item = line_with(2)
        ids = units_for(item).pluck(:id)
        Inventory.where(id: ids).update_all(status: status_value)

        expect(item.send(:free_inventory_scope).count).to eq(0)
        expect(item.update(quantity: 1)).to be(false)

        aggregate_failures do
          expect(item.reload.quantity).to eq(2)
          expect(Inventory.where(id: ids, status: status_value).count).to eq(2)
          expect(item.errors[:base].join).to match(/Not enough free inventory/)
        end
      end
    end

    it 'blocks a partial reduction that would exceed the free units' do
      item = line_with(3)
      ids = units_for(item).pluck(:id)
      Inventory.where(id: ids.first(2)).update_all(status: Inventory.statuses[:pre_reserved])

      expect(item.send(:free_inventory_scope).count).to eq(1)
      expect(item.update(quantity: 1)).to be(false)

      expect(item.reload.quantity).to eq(3)
      expect(Inventory.where(id: ids).count).to eq(3)
    end

    it 'never detaches a real customer commitment when the line quantity grows' do
      item = line_with(3)
      sale_order, sale_line = committed_sale_line(2)

      committed_ids = Inventory.where(sale_order_item_id: sale_line.id).order(:id).pluck(:id)
      expect(committed_ids.size).to eq(2)

      item.update!(quantity: 5)

      aggregate_failures do
        still = Inventory.where(id: committed_ids)
        expect(still.where(status: :pre_reserved).count).to eq(2)
        expect(still.pluck(:sale_order_id).uniq).to eq([sale_order.id])
        expect(still.pluck(:sale_order_item_id).uniq).to eq([sale_line.id])
      end
    end

    it 'never detaches a real customer commitment when the line quantity shrinks' do
      item = line_with(3)
      sale_order, sale_line = committed_sale_line(2)

      committed_ids = Inventory.where(sale_order_item_id: sale_line.id).order(:id).pluck(:id)
      expect(committed_ids.size).to eq(2)
      expect(item.send(:free_inventory_scope).count).to eq(1)

      item.update!(quantity: 2)

      aggregate_failures do
        still = Inventory.where(id: committed_ids)
        expect(still.where(status: :pre_reserved).count).to eq(2)
        expect(still.pluck(:sale_order_id).uniq).to eq([sale_order.id])
        expect(still.pluck(:sale_order_item_id).uniq).to eq([sale_line.id])
        # La única pieza libre fue la retirada.
        expect(units_for(item).where(status: :scrap).count).to eq(1)
      end
    end

    it 'retires only free units, never a committed one' do
      item = line_with(4)
      _sale_order, sale_line = committed_sale_line(2)
      committed_ids = Inventory.where(sale_order_item_id: sale_line.id).pluck(:id)

      item.update!(quantity: 2)

      aggregate_failures do
        expect(Inventory.where(id: committed_ids, status: :scrap).count).to eq(0)
        expect(units_for(item).where(status: :scrap).count).to eq(2)
        expect(units_for(item).where(status: :scrap).pluck(:sale_order_id).compact).to be_empty
      end
    end
  end
end
