require 'rails_helper'

RSpec.describe 'Admin::WhatsappRequests', type: :request do
  before(:all) { Rails.application.reload_routes! }

  let(:admin) { create(:user, role: :admin) }
  let(:customer) { create(:user, email: 'cliente@example.com') }
  let(:product) { create(:product, selling_price: 250, status: :active, seed_inventory_count: 3) }

  describe 'POST /admin/whatsapp_requests/:id/convert_to_sale_order' do
    let(:whatsapp_request) do
      create(:whatsapp_request, status: :sent, customer_name: 'Cliente Prueba', user: customer).tap do |req|
        create(:whatsapp_request_item, whatsapp_request: req, product: product, quantity: 2, unit_price_snapshot: 250)
      end
    end

    it 'creates the sale order with a complete line' do
      sign_in admin

      expect {
        post convert_to_sale_order_admin_whatsapp_request_path(whatsapp_request), params: { user_id: customer.id }
      }.to change(SaleOrder, :count).by(1)

      sale_order = SaleOrder.last
      item = sale_order.sale_order_items.first

      expect(sale_order.origin).to eq('whatsapp')
      expect(item.quantity).to eq(2)
      expect(item.unit_final_price).to eq(250)
      # unit_cost es NOT NULL y tiene validación de presencia: omitirlo hacía
      # que toda conversión abortara con RecordInvalid.
      expect(item.unit_cost).to be_present
      expect(item.total_line_cost).to eq(500)

      expect(whatsapp_request.reload.status).to eq('converted')
      expect(whatsapp_request.sale_order_id).to eq(sale_order.id)
      expect(whatsapp_request.converted_at).to be_present
    end
  end
end
