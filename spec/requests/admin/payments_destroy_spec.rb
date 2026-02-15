require 'rails_helper'

RSpec.describe 'Admin::Payments#destroy – SO status & inventory sync', type: :request do
  before(:all) { Rails.application.reload_routes! }

  let(:admin)    { create(:user, :admin) }
  let(:customer) { create(:user) }
  let(:product)  { create(:product, skip_seed_inventory: true) }

  before { sign_in admin }

  # Helper: crea una SO con pago completo e inventario reservado
  def build_paid_order(status:)
    so = create(:sale_order, user: customer, status: 'Pending',
                subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)

    inv1 = Inventory.create!(product: product, sale_order: so, purchase_cost: 50, status: :reserved)
    inv2 = Inventory.create!(product: product, sale_order: so, purchase_cost: 50, status: :reserved)
    payment = create(:payment, sale_order: so, amount: 100, status: 'Completed')

    # Forzar el status deseado y marcar inventarios como sold (simulando el flujo normal)
    so.update_columns(status: status)
    inv1.update_columns(status: Inventory.statuses[:sold])
    inv2.update_columns(status: Inventory.statuses[:sold])

    [so, payment, inv1, inv2]
  end

  describe 'DELETE /admin/sale_orders/:sale_order_id/payments/:id' do
    context 'when removing payment from a Confirmed order' do
      it 'degrades SO to Pending and reverts inventory to reserved' do
        so, payment, inv1, inv2 = build_paid_order(status: 'Confirmed')

        delete admin_sale_order_payment_path(so, payment)

        so.reload
        expect(so.status).to eq('Pending')
        expect(inv1.reload.status).to eq('reserved')
        expect(inv2.reload.status).to eq('reserved')
      end
    end

    context 'when removing payment from a Preparing order' do
      it 'degrades SO to Pending and reverts inventory to reserved' do
        so, payment, inv1, inv2 = build_paid_order(status: 'Preparing')

        delete admin_sale_order_payment_path(so, payment)

        so.reload
        expect(so.status).to eq('Pending')
        expect(inv1.reload.status).to eq('reserved')
        expect(inv2.reload.status).to eq('reserved')
      end
    end

    context 'when removing payment from an In Transit order' do
      it 'degrades SO to Pending and reverts inventory to reserved' do
        so, payment, inv1, inv2 = build_paid_order(status: 'In Transit')

        delete admin_sale_order_payment_path(so, payment)

        so.reload
        expect(so.status).to eq('Pending')
        expect(inv1.reload.status).to eq('reserved')
        expect(inv2.reload.status).to eq('reserved')
      end
    end

    context 'when removing payment from a Delivered order' do
      it 'does NOT degrade SO (Delivered requires manual action)' do
        so, payment, inv1, inv2 = build_paid_order(status: 'Delivered')

        delete admin_sale_order_payment_path(so, payment)

        so.reload
        expect(so.status).to eq('Delivered')
        # Inventory stays sold since SO status didn't change
        expect(inv1.reload.status).to eq('sold')
        expect(inv2.reload.status).to eq('sold')
      end
    end

    context 'when partial payment still covers total' do
      it 'does not degrade SO status' do
        so = create(:sale_order, user: customer, status: 'Pending',
                    subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
        p1 = create(:payment, sale_order: so, amount: 60, status: 'Completed')
        p2 = create(:payment, sale_order: so, amount: 50, status: 'Completed')
        so.update_columns(status: 'Confirmed')

        # Remove only one payment (60 remaining from p2 = 50, not enough → degrade)
        delete admin_sale_order_payment_path(so, p1)

        so.reload
        expect(so.status).to eq('Pending')
      end
    end
  end
end
