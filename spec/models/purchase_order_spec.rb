require 'rails_helper'

RSpec.describe PurchaseOrder, type: :model do
  let(:supplier) { create(:user, :supplier) }
  let(:product)  { create(:product) }
  describe "Associations" do
    it { should belong_to(:user) }
    it { should have_many(:inventories) }
  end

  describe "Validations" do
    it { should validate_presence_of(:order_date) }
    it { should validate_presence_of(:expected_delivery_date) }
    it { should validate_presence_of(:status) }

    # Los campos numéricos son normalizados a 0 y recalculados; no probamos presence/numericality directos
  end

  describe 'publication reconciliation after receipt' do
    let(:product) { create(:product, skip_seed_inventory: true) }
    let(:purchase_order) { create(:purchase_order, user: supplier, status: 'In Transit') }
    let!(:inventory) do
      create(:inventory, product: product, purchase_order: purchase_order, status: :in_transit)
    end

    it 'enqueues reconciliation after inventory is received as available' do
      allow(Products::ReconcilePublicationJob).to receive(:perform_later) do
        expect(inventory.reload).to be_available
      end

      purchase_order.update!(status: 'Delivered')

      expect(Products::ReconcilePublicationJob).to have_received(:perform_later).once
    end

    it 'auto-pauses an active product received without a location when reconciliation runs' do
      allow(Products::ReconcilePublicationJob).to receive(:perform_later) do
        Products::ReconcilePublicationJob.perform_now
      end

      purchase_order.update!(status: 'Delivered')

      expect(product.reload).to be_inactive
      expect(product.auto_paused).to be(true)
    end

    it 'does not enqueue reconciliation for another status transition' do
      allow(Products::ReconcilePublicationJob).to receive(:perform_later)

      purchase_order.update!(status: 'Canceled')

      expect(Products::ReconcilePublicationJob).not_to have_received(:perform_later)
    end

    it 'does not enqueue reconciliation when another status transitions directly to Delivered' do
      pending_order = create(:purchase_order, user: supplier, status: 'Pending')
      allow(Products::ReconcilePublicationJob).to receive(:perform_later)

      pending_order.update!(status: 'Delivered')

      expect(Products::ReconcilePublicationJob).not_to have_received(:perform_later)
    end

    it 'does not enqueue reconciliation when an update leaves the status unchanged' do
      delivered_order = create(:purchase_order, user: supplier, status: 'Delivered')
      allow(Products::ReconcilePublicationJob).to receive(:perform_later)

      delivered_order.update!(notes: 'Status remains delivered')

      expect(Products::ReconcilePublicationJob).not_to have_received(:perform_later)
    end

    it 'does not enqueue reconciliation when the receipt transaction rolls back' do
      allow(Products::ReconcilePublicationJob).to receive(:perform_later)

      PurchaseOrder.transaction(requires_new: true) do
        purchase_order.update!(status: 'Delivered')
        raise ActiveRecord::Rollback
      end

      expect(purchase_order.reload.status).to eq('In Transit')
      expect(Products::ReconcilePublicationJob).not_to have_received(:perform_later)
    end
  end

  describe "Numeric normalization and totals" do
    it "normalizes nil and invalid numeric fields to 0 and keeps provided totals when no items" do
      po = PurchaseOrder.new(
        order_date: Date.today,
        expected_delivery_date: Date.today + 1,
        currency: 'USD',
        exchange_rate: '17.5',
        subtotal: nil,
        shipping_cost: 'abcd',
        tax_cost: nil,
        other_cost: nil,
        total_order_cost: 117,
        status: 'Delivered',
        user: supplier
      )
      expect(po).to be_valid
      po.save!
      expect(po.subtotal.to_d).to eq(0)
      expect(po.shipping_cost.to_d).to eq(0)
      expect(po.tax_cost.to_d).to eq(0)
      expect(po.other_cost.to_d).to eq(0)
      # total_order_cost permanece tal cual al no haber líneas
      expect(po.total_order_cost.to_d).to eq(117)
      # total_cost_mxn calculado desde total_order_cost y tipo de cambio
      expect(po.total_cost_mxn.to_d).to eq((117 * 17.5).to_d)
    end

    it "recalculates subtotal and totals from items when present" do
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending')
  create(:purchase_order_item, purchase_order: po, product: product, quantity: 2, unit_cost: 50, unit_additional_cost: 0)
      po.reload
      # subtotal 100, costos 0 por default
      expect(po.subtotal.to_d).to eq(100)
      expect(po.total_order_cost.to_d).to eq(100)
      expect(po.total_cost_mxn.to_d).to eq(100)
    end

    it "does not double-count header costs when distributed line totals exist" do
      # PO con costos de envío/impuestos en encabezado pero líneas ya distribuidas
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending', shipping_cost: 30, tax_cost: 20, other_cost: 0)

      # Dos líneas: A (2x50 con +10 adicional unitario) => 120; B (1x100 con +30 adicional unitario) => 130; total = 250
      item_a = create(:purchase_order_item, purchase_order: po, product: product, quantity: 2, unit_cost: 50,
                          unit_additional_cost: 10, unit_compose_cost: 60, total_line_cost: 120)
      item_b = create(:purchase_order_item, purchase_order: po, product: product, quantity: 1, unit_cost: 100,
                          unit_additional_cost: 30, unit_compose_cost: 130, total_line_cost: 130)

      # Marcar que los costos fueron distribuidos y forzar recalculo
      po.update_column(:costs_distributed_at, Time.current)
      po.recalculate_totals!
      po.reload

      # La suma de líneas ya incluye los 50 de adicionales; total_order_cost debe igualar subtotal, no sumar shipping/tax otra vez.
      expect(po.subtotal.to_d).to eq(250)
      expect(po.total_order_cost.to_d).to eq(250)
      expect(po.total_cost_mxn.to_d).to eq(250)
    end

    it "sums header costs when costs_distributed_at is nil" do
      # PO sin distribución aplicada (costs_distributed_at = nil)
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending',
                  shipping_cost: 30, tax_cost: 20, other_cost: 0, costs_distributed_at: nil)

      # Línea simple sin costos distribuidos
      create(:purchase_order_item, purchase_order: po, product: product, quantity: 2, unit_cost: 50)

      po.reload

      # Sin distribución: subtotal = base (100), total = base + encabezado (100 + 50 = 150)
      expect(po.subtotal.to_d).to eq(100)
      expect(po.total_order_cost.to_d).to eq(150)
      expect(po.total_cost_mxn.to_d).to eq(150)
    end
  end



  describe "costs_distributed_at clearing logic" do
    it "clears costs_distributed_at when header costs change" do
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending',
                  shipping_cost: 30, tax_cost: 20, other_cost: 0)

      # Simular que se distribuyeron costos
      po.update_column(:costs_distributed_at, 1.hour.ago)
      expect(po.costs_distributed_at).to be_present

      # Cambiar shipping_cost debería limpiar el timestamp
      po.update(shipping_cost: 50)
      expect(po.costs_distributed_at).to be_nil
    end

    it "clears costs_distributed_at when tax_cost changes" do
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending',
                  shipping_cost: 30, tax_cost: 20, other_cost: 0)

      po.update_column(:costs_distributed_at, 1.hour.ago)
      po.update(tax_cost: 25)
      expect(po.costs_distributed_at).to be_nil
    end

    it "clears costs_distributed_at when other_cost changes" do
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending',
                  shipping_cost: 30, tax_cost: 20, other_cost: 10)

      po.update_column(:costs_distributed_at, 1.hour.ago)
      po.update(other_cost: 15)
      expect(po.costs_distributed_at).to be_nil
    end

    it "does not clear costs_distributed_at when other fields change" do
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending',
                  shipping_cost: 30, tax_cost: 20, other_cost: 0)

      po.update_column(:costs_distributed_at, 1.hour.ago)
      original_timestamp = po.costs_distributed_at

      po.update(status: 'In Transit')
      expect(po.costs_distributed_at).to eq(original_timestamp)
    end
  end

  describe "costs_distributed_at clearing on item changes" do
    it "clears costs_distributed_at when an item quantity changes" do
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending')
      item = create(:purchase_order_item, purchase_order: po, product: product, quantity: 2, unit_cost: 50)

      # Simular distribución de costos
      po.update_column(:costs_distributed_at, 1.hour.ago)
      expect(po.costs_distributed_at).to be_present

      # Cambiar cantidad del item
      item.update(quantity: 3)
      po.reload
      expect(po.costs_distributed_at).to be_nil
    end

    it "clears costs_distributed_at when a new item is added" do
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending')
      create(:purchase_order_item, purchase_order: po, product: product, quantity: 2, unit_cost: 50)

      po.update_column(:costs_distributed_at, 1.hour.ago)

      # Agregar nuevo item
      product2 = create(:product, product_sku: 'PROD-002')
      create(:purchase_order_item, purchase_order: po, product: product2, quantity: 1, unit_cost: 100)

      po.reload
      expect(po.costs_distributed_at).to be_nil
    end

    it "clears costs_distributed_at when an item is deleted" do
      po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending')
      item1 = create(:purchase_order_item, purchase_order: po, product: product, quantity: 2, unit_cost: 50)
      product2 = create(:product, product_sku: 'PROD-002')
      item2 = create(:purchase_order_item, purchase_order: po, product: product2, quantity: 1, unit_cost: 100)

      po.update_column(:costs_distributed_at, 1.hour.ago)

      # Eliminar un item
      item2.destroy

      po.reload
      expect(po.costs_distributed_at).to be_nil
    end
  end

  describe "Custom Validations" do
    it "validates that actual_delivery_date is after expected_delivery_date" do
      purchase_order = PurchaseOrder.new(
        order_date: Date.today,
        expected_delivery_date: Date.today + 5.days,
        actual_delivery_date: Date.today + 3.days, # Invalid case
        subtotal: 100.0,
        total_order_cost: 120.0,
        shipping_cost: 10.0,
        tax_cost: 5.0,
        other_cost: 5.0,
        status: "Pending",
        user: User.new(name: "Supplier Test", email: "supplier@test.com", password: "password", role: "supplier")
      )
      expect(purchase_order).to_not be_valid
      expect(purchase_order.errors[:actual_delivery_date]).to include("must be after or equal to expected delivery date")
    end
  end

  it "deletes free inventories and destroys the PO" do
    po = create(:purchase_order, user: supplier)
    create(:purchase_order_item, purchase_order: po, product: product, quantity: 2)

    expect { po.destroy }.to change { PurchaseOrder.count }.by(-1)
    expect(Inventory.where(purchase_order_id: po.id)).to be_empty
  end

  it "allocates delivered inventory only after location assignment and then blocks PO destroy" do
    product = create(:product, skip_seed_inventory: true)
    po  = create(:purchase_order, user: supplier, order_date: Date.today, expected_delivery_date: Date.today, status: "Pending")
    create(:purchase_order_item, purchase_order: po, product: product, quantity: 1, unit_cost: 100)
    po.update!(status: "Delivered") # ensures inventories flip to :available via after_update

    inventory = Inventory.find_by!(purchase_order_id: po.id, product_id: product.id)
    customer = create(:user)
    so = create(:sale_order, user: customer)
    line = create(:sale_order_item, sale_order: so, product: product, quantity: 1, unit_final_price: 150)

    expect(inventory.reload).to be_available
    expect(inventory.inventory_location_id).to be_nil
    expect(inventory.sale_order_id).to be_nil
    expect(Inventory.customer_sellable.where(id: inventory.id)).to be_empty

    inventory.update!(inventory_location: create(:inventory_location))
    expect(Inventory.customer_sellable.where(id: inventory.id)).to exist

    InventoryServices::ReserveSaleOrderItem.call(line)
    expect(inventory.reload).to be_reserved
    expect(inventory.sale_order).to eq(so)
    expect(inventory.sale_order_item).to eq(line)

    # Sanity: confirm a locked row for this PO exists
    locked = Inventory.where(purchase_order_id: po.id)
                      .where(status: [:reserved, :sold])
                      .or(Inventory.where(purchase_order_id: po.id).where.not(sale_order_id: nil))
    expect(locked.exists?).to be(true)

    # Destroy should be blocked; record remains; error present
    po.reload
    expect(po.destroyed?).to be_falsey
    expect { po.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(po.persisted?).to be(true)
  end
end
