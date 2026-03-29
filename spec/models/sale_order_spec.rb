require 'rails_helper'

RSpec.describe SaleOrder, type: :model do
  let(:customer) { create(:user, role: "customer") }
  let(:product)  { create(:product, skip_seed_inventory: true) }

  it "destroys and releases reserved items" do
    so = create(:sale_order, user: customer, status: "Pending")
    create(:sale_order_item, sale_order: so, product: product, quantity: 2)
    # crea inventories reserved vía callback

    expect { so.destroy }.to change { SaleOrder.count }.by(-1)
    expect(Inventory.where(sale_order_id: so.id)).to be_empty
  end

  it "blocks destroy when sold exists" do
    customer = create(:user, role: "customer")
    prod     = create(:product, skip_seed_inventory: true)

    so  = create(:sale_order, user: customer, status: "Pending", subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
    soi = create(:sale_order_item, sale_order: so, product: prod, quantity: 1, unit_final_price: 100, total_line_cost: 100)

    inv = Inventory.find_by(sale_order_id: so.id, product_id: prod.id) ||
          Inventory.create!(product: prod, sale_order_id: so.id, purchase_cost: 100, status: :reserved)

    inv.update!(status: :sold)

    expect(so.destroy).to be_falsey
    expect(SaleOrder.exists?(so.id)).to be(true)
    expect { so.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed, /Failed to destroy SaleOrderItem/)
  end

  # ---------------------------------------------------------------------------
  # update_status_if_fully_paid! – Degradación de status al quitar pago
  # ---------------------------------------------------------------------------
  describe '#update_status_if_fully_paid!' do
    let(:so) do
      create(:sale_order, user: customer, status: 'Pending',
             subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
    end

    context 'when fully paid' do
      before { create(:payment, sale_order: so, amount: 100, status: 'Completed') }

      it 'promotes Pending → Confirmed' do
        so.update_status_if_fully_paid!
        expect(so.reload.status).to eq('Confirmed')
      end

      it 'does not change status if already beyond Confirmed' do
        so.update_columns(status: 'Preparing')
        so.update_status_if_fully_paid!
        expect(so.reload.status).to eq('Preparing')
      end
    end

    context 'when payment removed from Confirmed order' do
      before do
        create(:payment, sale_order: so, amount: 100, status: 'Completed')
        so.update_status_if_fully_paid!       # → Confirmed
        expect(so.reload.status).to eq('Confirmed')
      end

      it 'degrades Confirmed → Pending' do
        so.payments.destroy_all
        so.reload.update_status_if_fully_paid!
        expect(so.reload.status).to eq('Pending')
      end
    end

    context 'when payment removed from Preparing order' do
      before do
        create(:payment, sale_order: so, amount: 100, status: 'Completed')
        so.update_columns(status: 'Preparing')
      end

      it 'degrades Preparing → Pending' do
        so.payments.destroy_all
        so.reload.update_status_if_fully_paid!
        expect(so.reload.status).to eq('Pending')
      end
    end

    context 'when payment removed from In Transit order' do
      before do
        create(:payment, sale_order: so, amount: 100, status: 'Completed')
        so.update_columns(status: 'In Transit')
      end

      it 'degrades In Transit → Pending' do
        so.payments.destroy_all
        so.reload.update_status_if_fully_paid!
        expect(so.reload.status).to eq('Pending')
      end
    end

    context 'when payment removed from Delivered order' do
      before do
        create(:payment, sale_order: so, amount: 100, status: 'Completed')
        so.update_columns(status: 'Delivered')
      end

      it 'does NOT degrade Delivered (requires manual action)' do
        so.payments.destroy_all
        so.reload.update_status_if_fully_paid!
        expect(so.reload.status).to eq('Delivered')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # sync_inventory_status_for_payment_change – Reversión de inventario
  # ---------------------------------------------------------------------------
  describe '#sync_inventory_status_for_payment_change' do
    let(:so) do
      create(:sale_order, user: customer, status: 'Pending',
             subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
    end

    let!(:inv1) do
      Inventory.create!(product: product, sale_order: so, purchase_cost: 50, status: :reserved)
    end

    let!(:inv2) do
      Inventory.create!(product: product, sale_order: so, purchase_cost: 50, status: :reserved)
    end

    context 'when promoting Pending → Confirmed' do
      before { create(:payment, sale_order: so, amount: 100, status: 'Completed') }

      it 'changes inventory from reserved to sold' do
        so.update!(status: 'Confirmed')
        expect(inv1.reload.status).to eq('sold')
        expect(inv2.reload.status).to eq('sold')
      end
    end

    context 'when demoting Confirmed → Pending' do
      before { so.update_columns(status: 'Confirmed') }
      before { inv1.update_columns(status: Inventory.statuses[:sold]) }
      before { inv2.update_columns(status: Inventory.statuses[:sold]) }

      it 'changes inventory from sold to reserved' do
        so.update!(status: 'Pending')
        expect(inv1.reload.status).to eq('reserved')
        expect(inv2.reload.status).to eq('reserved')
      end
    end

    context 'when demoting Preparing → Pending (payment removed)' do
      before { so.update_columns(status: 'Preparing') }
      before { inv1.update_columns(status: Inventory.statuses[:sold]) }
      before { inv2.update_columns(status: Inventory.statuses[:sold]) }

      it 'changes inventory from sold to reserved' do
        so.update!(status: 'Pending')
        expect(inv1.reload.status).to eq('reserved')
        expect(inv2.reload.status).to eq('reserved')
      end
    end

    context 'when demoting In Transit → Pending (payment removed)' do
      before { so.update_columns(status: 'In Transit') }
      before { inv1.update_columns(status: Inventory.statuses[:sold]) }
      before { inv2.update_columns(status: Inventory.statuses[:sold]) }

      it 'changes inventory from sold to reserved' do
        so.update!(status: 'Pending')
        expect(inv1.reload.status).to eq('reserved')
        expect(inv2.reload.status).to eq('reserved')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Inventory pre_reserved/pre_sold – Piezas en tránsito del proveedor
  # ---------------------------------------------------------------------------
  describe 'inventory from supplier in transit' do
    let(:so) do
      create(:sale_order, user: customer, status: 'Confirmed',
             subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
    end

    it 'detects pre_reserved pieces (PO in transit, SO pending)' do
      Inventory.create!(product: product, sale_order: so, purchase_cost: 50, status: :pre_reserved)

      count = so.inventories.where(status: %i[pre_reserved pre_sold in_transit]).count
      expect(count).to eq(1)
    end

    it 'detects pre_sold pieces (PO in transit, SO confirmed)' do
      Inventory.create!(product: product, sale_order: so, purchase_cost: 50, status: :pre_sold)

      count = so.inventories.where(status: %i[pre_reserved pre_sold in_transit]).count
      expect(count).to eq(1)
    end

    it 'returns zero when all pieces are reserved (in warehouse)' do
      Inventory.create!(product: product, sale_order: so, purchase_cost: 50, status: :reserved)

      count = so.inventories.where(status: %i[pre_reserved pre_sold in_transit]).count
      expect(count).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # update_status_if_fully_paid! – Credit orders should NOT be demoted
  # ---------------------------------------------------------------------------
  describe '#update_status_if_fully_paid! with credit' do
    let(:credit_customer) { create(:user, role: 'customer', credit_enabled: true, default_credit_terms: 'net30') }

    let(:so) do
      create(:sale_order, user: credit_customer, status: 'Pending',
             subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
    end

    context 'when customer has credit_enabled' do
      it 'does NOT demote Confirmed → Pending without payment' do
        so.update_columns(status: 'Confirmed')
        so.update_status_if_fully_paid!
        expect(so.reload.status).to eq('Confirmed')
      end

      it 'does NOT demote Preparing → Pending without payment' do
        so.update_columns(status: 'Preparing')
        so.update_status_if_fully_paid!
        expect(so.reload.status).to eq('Preparing')
      end

      it 'does NOT demote In Transit → Pending without payment' do
        so.update_columns(status: 'In Transit')
        so.update_status_if_fully_paid!
        expect(so.reload.status).to eq('In Transit')
      end

      it 'still promotes Pending → Confirmed when fully paid' do
        create(:payment, sale_order: so, amount: 100, status: 'Completed')
        so.update_status_if_fully_paid!
        expect(so.reload.status).to eq('Confirmed')
      end
    end

    context 'when order has credit_override' do
      let(:regular_customer) { create(:user, role: 'customer', credit_enabled: false) }
      let(:override_so) do
        create(:sale_order, user: regular_customer, status: 'Pending',
               subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100,
               credit_override: true)
      end

      it 'does NOT demote Confirmed → Pending without payment' do
        override_so.update_columns(status: 'Confirmed')
        override_so.update_status_if_fully_paid!
        expect(override_so.reload.status).to eq('Confirmed')
      end
    end

    context 'when NOT credit enabled (regression)' do
      let(:regular_customer) { create(:user, role: 'customer', credit_enabled: false) }
      let(:regular_so) do
        create(:sale_order, user: regular_customer, status: 'Pending',
               subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
      end

      it 'still demotes Confirmed → Pending without payment' do
        regular_so.update_columns(status: 'Confirmed')
        regular_so.update_status_if_fully_paid!
        expect(regular_so.reload.status).to eq('Pending')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Reservation notes management
  # ---------------------------------------------------------------------------
  describe 'reservation note management' do
    let(:so) do
      create(:sale_order, user: customer, status: 'Pending',
             subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
    end
    let!(:soi) { create(:sale_order_item, sale_order: so, product: product, quantity: 3) }

    describe '#upsert_pending_note' do
      it 'adds a shortage note' do
        so.upsert_pending_note(soi, 2)
        expect(so.reload.notes).to include("🛑 Producto")
        expect(so.notes).to include("cliente pidió 3, solo reservados 1")
      end

      it 'replaces existing note for same line' do
        so.upsert_pending_note(soi, 2)
        so.upsert_pending_note(soi, 1)
        lines = so.reload.notes.split("\n").select { |l| l.include?("línea #{soi.id}") }
        expect(lines.count).to eq(1)
        expect(lines.first).to include("solo reservados 2")
      end
    end

    describe '#remove_pending_note_for' do
      it 'removes the note for a specific line' do
        so.upsert_pending_note(soi, 2)
        expect(so.reload.notes).to include("🛑 Producto")

        so.remove_pending_note_for(soi)
        expect(so.reload.notes).not_to include("🛑 Producto")
      end

      it 'preserves notes for other lines' do
        product2 = create(:product, skip_seed_inventory: true)
        soi2 = create(:sale_order_item, sale_order: so, product: product2, quantity: 1)
        so.upsert_pending_note(soi, 2)
        so.upsert_pending_note(soi2, 1)

        so.remove_pending_note_for(soi)
        expect(so.reload.notes).not_to include(product.product_name)
        expect(so.notes).to include(product2.product_name)
      end
    end
  end
end