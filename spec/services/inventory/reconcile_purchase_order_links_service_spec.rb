require 'rails_helper'

RSpec.describe InventoryReconciliation::ReconcilePurchaseOrderLinksService, type: :service do
  let!(:product) { create(:product, skip_seed_inventory: true) }
  let!(:po) { create(:purchase_order) }
  let!(:poi) { create(:purchase_order_item, purchase_order: po, product: product, quantity: 2, unit_cost: 10) }

  it 'creates missing inventory pieces' do
    # Aseguramos eliminar cualquier sync previo (si existiera callback futuro)
    Inventory.where(purchase_order_item_id: poi.id).delete_all
    expect(Inventory.where(purchase_order_item_id: poi.id).count).to eq(0)
    result = described_class.new(dry_run: false).call
    expect(result.created_missing).to eq(2)
  end

  # Huérfana = pieza viva cuya línea de compra ya no existe. Quitar una línea
  # ya retira sus piezas; esto limpia datos heredados (línea borrada sin
  # callbacks, como pasaba antes).
  def orphan_line!
    poi.delete
    Inventory.where(purchase_order_item_id: poi.id).order(:id).to_a
  end

  it 'destroys orphan inventory pieces' do
    orphans = orphan_line!

    result = described_class.new(dry_run: false, mode: :orphans).call

    expect(result.errors).to be_empty
    expect(result.destroyed_orphans).to eq(2)
    expect(Inventory.where(id: orphans)).to be_empty
  end

  it 'retires an orphan that has audit history instead of failing the whole run' do
    with_history, plain = orphan_line!
    InventoryEvent.create!(inventory: with_history, product_id: product.id, event_type: 'status_change', metadata: {})

    result = described_class.new(dry_run: false, mode: :orphans).call

    aggregate_failures do
      expect(result.errors).to be_empty
      expect(result.destroyed_orphans).to eq(2)
      expect(with_history.reload).to be_scrap
      expect(Inventory.where(id: plain.id)).to be_empty
      expect(Inventory.customer_sellable.where(product: product)).to be_empty
    end
  end

  it 'never touches an orphan that belongs to a customer' do
    committed, = orphan_line!
    committed.update_columns(status: Inventory.statuses[:pre_reserved], sale_order_id: create(:sale_order).id)

    described_class.new(dry_run: false, mode: :orphans).call

    expect(committed.reload).to be_pre_reserved
  end

  it 'leaves retired pieces alone' do
    orphan_line!.each { |inv| inv.update_columns(status: Inventory.statuses[:scrap]) }

    expect(described_class.new(dry_run: false, mode: :orphans).call.destroyed_orphans).to eq(0)
  end

  it 'does not persist changes in dry_run' do
  Inventory.where(purchase_order_item_id: poi.id).delete_all
  # Cambiamos cantidad sin callbacks para no recrear inventario antes de dry_run
  poi.update_columns(quantity: 5)
  Inventory.where(purchase_order_item_id: poi.id).delete_all # limpieza extra por si sync previo
  expect(Inventory.where(purchase_order_item_id: poi.id).count).to eq(0)
  result = described_class.new(dry_run: true).call
  expect(result.created_missing).to eq(5) # reporta lo que habría creado
    # Should still be zero pieces because dry_run
    expect(Inventory.where(purchase_order_item_id: poi.id).count).to eq(0)
  end
end
