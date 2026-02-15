require 'rails_helper'

RSpec.describe 'Admin::SaleOrders#deliver', type: :request do
  before(:all) { Rails.application.reload_routes! }

  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }

  before { sign_in admin }

  describe 'POST /admin/sale_orders/:id/deliver' do
    context 'when order is In Transit with a shipment' do
      let(:sale_order) { create(:sale_order, user: customer, status: 'In Transit', credit_override: true) }
      let!(:shipment) { create(:shipment, sale_order: sale_order, status: :shipped) }

      it 'transitions the order to Delivered' do
        post deliver_admin_sale_order_path(sale_order)

        expect(response).to redirect_to(admin_sale_order_path(sale_order))
        follow_redirect!
        expect(response.body).to include('Orden marcada como entregada')

        sale_order.reload
        expect(sale_order.status).to eq('Delivered')

        shipment.reload
        expect(shipment.status).to eq('delivered')
      end
    end

    context 'when order is NOT In Transit' do
      %w[Pending Confirmed Preparing Delivered Canceled].each do |status|
        it "rejects deliver when status is #{status}" do
          sale_order = create(:sale_order, user: customer, status: status)

          post deliver_admin_sale_order_path(sale_order)

          expect(response).to redirect_to(admin_sale_order_path(sale_order))
          follow_redirect!
          expect(response.body).to include('Solo se puede marcar como entregada una orden en tránsito')
        end
      end
    end

    context 'when order has no shipment' do
      let(:sale_order) { create(:sale_order, user: customer, status: 'In Transit') }

      it 'rejects and shows alert' do
        post deliver_admin_sale_order_path(sale_order)

        expect(response).to redirect_to(admin_sale_order_path(sale_order))
        follow_redirect!
        expect(response.body).to include('No hay envío asignado')
      end
    end
  end
end
