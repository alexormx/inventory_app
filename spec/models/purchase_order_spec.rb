require 'rails_helper'

RSpec.describe PurchaseOrder, type: :model do
  let(:supplier) { create(:user, :supplier) }
  let(:product)  { create(:product) }
  describe "Associations" do
    it { should belong_to(:user) }
    it { should have_many(:inventories).with_foreign_key("purchase_order_id") }
  end

  describe "Validations" do
    it { should validate_presence_of(:order_date) }
    it { should validate_presence_of(:expected_delivery_date) }
    it { should validate_presence_of(:status) }

    # Los campos numéricos son normalizados a 0 y recalculados; no probamos presence/numericality directos
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

  it "blocks destroy when reserved/sold exists" do
    po  = create(:purchase_order, user: supplier, order_date: Date.today, expected_delivery_date: Date.today, status: "Pending")
    create(:purchase_order_item, purchase_order: po, product: product, quantity: 1, unit_cost: 100)
    po.update!(status: "Delivered") # ensures inventories flip to :available via after_update

    # Reserve that item via a Sale Order Item (no manual Inventory.create!)
    customer = create(:user)
    so = create(:sale_order, user: customer)
    create(:sale_order_item, sale_order: so, product: product, quantity: 1, unit_final_price: 150)

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