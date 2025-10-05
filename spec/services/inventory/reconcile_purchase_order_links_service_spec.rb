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

  it 'destroys orphan inventory pieces' do
    inv = Inventory.create!(product: product, purchase_order_id: po.id, purchase_order_item_id: poi.id, purchase_cost: 10, status: :in_transit)
    poi.destroy
    result = described_class.new(dry_run: false).call
    expect(result.destroyed_orphans).to be >= 1
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
