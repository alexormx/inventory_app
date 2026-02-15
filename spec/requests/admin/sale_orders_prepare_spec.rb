require 'rails_helper'

RSpec.describe 'Admin::SaleOrders#prepare', type: :request do
  before(:all) { Rails.application.reload_routes! }

  let(:admin)    { create(:user, :admin) }
  let(:customer) { create(:user) }
  let(:product)  { create(:product, skip_seed_inventory: true) }

  before { sign_in admin }

  describe 'GET /admin/sale_orders/:id/prepare' do
    context 'when order is Confirmed with reserved inventory' do
      let(:sale_order) do
        create(:sale_order, user: customer, status: 'Confirmed',
               subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
      end

      before do
        Inventory.create!(product: product, sale_order: sale_order, purchase_cost: 50, status: :reserved)
        create(:payment, sale_order: sale_order, amount: 100, status: 'Completed')
      end

      it 'transitions to Preparing and renders picking list' do
        get prepare_admin_sale_order_path(sale_order)

        expect(response).to have_http_status(:ok)
        sale_order.reload
        expect(sale_order.status).to eq('Preparing')
      end
    end

    context 'when order has inventory pieces in transit from supplier' do
      let(:sale_order) do
        create(:sale_order, user: customer, status: 'Confirmed',
               subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
      end

      before do
        # Simular pieza aún en tránsito del proveedor (pre_sold = SO confirmada + PO en tránsito)
        Inventory.create!(product: product, sale_order: sale_order, purchase_cost: 50, status: :pre_sold)
        create(:payment, sale_order: sale_order, amount: 100, status: 'Completed')
      end

      it 'rejects and redirects with alert about in-transit pieces' do
        get prepare_admin_sale_order_path(sale_order)

        expect(response).to redirect_to(admin_sale_order_path(sale_order))
        follow_redirect!
        expect(response.body).to include('en tránsito del proveedor')

        sale_order.reload
        expect(sale_order.status).to eq('Confirmed')
      end
    end

    context 'when order has mix of reserved and pre_reserved inventory' do
      let(:sale_order) do
        create(:sale_order, user: customer, status: 'Confirmed',
               subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
      end

      before do
        Inventory.create!(product: product, sale_order: sale_order, purchase_cost: 50, status: :reserved)
        Inventory.create!(product: product, sale_order: sale_order, purchase_cost: 50, status: :pre_reserved)
        create(:payment, sale_order: sale_order, amount: 100, status: 'Completed')
      end

      it 'rejects if any piece is pre_reserved' do
        get prepare_admin_sale_order_path(sale_order)

        expect(response).to redirect_to(admin_sale_order_path(sale_order))
        follow_redirect!
        expect(response.body).to include('1 pieza(s) aún en tránsito')

        sale_order.reload
        expect(sale_order.status).to eq('Confirmed')
      end
    end

    context 'when order is NOT Confirmed or Preparing' do
      %w[Pending Delivered Canceled].each do |status|
        it "rejects prepare when status is #{status}" do
          sale_order = create(:sale_order, user: customer, status: status)

          get prepare_admin_sale_order_path(sale_order)

          expect(response).to redirect_to(admin_sale_order_path(sale_order))
          follow_redirect!
          expect(response.body).to include('Solo se puede preparar una orden Confirmada')
        end
      end
    end
  end
end
