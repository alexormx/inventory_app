# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin sale orders: blank deletion and requested shipping', type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  describe 'DELETE /admin/sale_orders/:id' do
    it 'deletes a blank order and shows the button only for it' do
      order = create(:sale_order, total_order_value: 0, subtotal: 0)

      get admin_sale_order_path(order)
      expect(response.body).to include('Eliminar orden en blanco')

      delete admin_sale_order_path(order)

      expect(response).to redirect_to(admin_sale_orders_path)
      expect(SaleOrder.exists?(order.id)).to be(false)
    end

    it 'explains why an empty order cannot be deleted' do
      order = create(:sale_order, total_order_value: 0, subtotal: 0)
      create(:shipment, sale_order: order, status: :shipped)

      get admin_sale_order_path(order)

      expect(response.body).to include('No se puede eliminar: el envío ya se despachó')
    end

    it 'refuses orders with products and explains why' do
      order = create(:sale_order)
      create(:sale_order_item, sale_order: order)

      get admin_sale_order_path(order)
      expect(response.body).not_to include('Eliminar orden en blanco')

      delete admin_sale_order_path(order)

      expect(response).to redirect_to(admin_sale_order_path(order))
      expect(flash[:alert]).to include('tiene productos')
      expect(SaleOrder.exists?(order.id)).to be(true)
    end
  end

  describe 'shipping chosen by the customer' do
    let(:order) { create(:sale_order, shipping_cost: 149) }

    before do
      create(:order_shipping_address, sale_order: order, shipping_method: 'envio_local',
                                      raw_address_json: { 'shipping_method_name' => 'Envío Local (CDMX)' })
    end

    it 'is shown inside the single shipment section before a shipment is registered' do
      get admin_sale_order_path(order)

      section = Nokogiri::HTML(response.body).at_css('#shipment-section')
      expect(section.text).to include('Aún no se registra el envío', 'Solicitado por el cliente en la tienda',
                                      'Envío Local (CDMX)', '$149.00')
      expect(response.body).to include('Agregar envío')
    end

    it 'keeps one editable shipment section, with the customer request as reference' do
      create(:shipment, sale_order: order, carrier: 'Estafeta', tracking_number: 'G123')

      get admin_sale_order_path(order)

      doc = Nokogiri::HTML(response.body)
      expect(doc.css('#shipment-section').size).to eq(1)
      expect(doc.at_css('#shipment-section').text).to include('Estafeta', 'G123', 'Solicitado por el cliente en la tienda')
      expect(response.body).to include('Editar envío', 'Eliminar envío')
      expect(response.body).not_to include('Agregar envío')
    end

    it 'refuses a second shipment for the same order' do
      create(:shipment, sale_order: order)

      post admin_sale_order_shipments_path(order),
           params: { shipment: { carrier: 'DHL', estimated_delivery: Date.current } }

      expect(Shipment.where(sale_order_id: order.id).count).to eq(1)
    end

    it 'pre-fills the carrier of a new shipment' do
      get new_admin_sale_order_shipment_path(order)

      expect(response.body).to include('value="Envío Local (CDMX)"')
    end

    it 'marks store pickup as personal delivery' do
      order.order_shipping_address.update!(shipping_method: 'recoger_tienda',
                                           raw_address_json: { 'shipping_method_name' => 'Recoger en Tienda' })

      expect(order.reload.requested_shipment_attributes).to eq(carrier: 'Recoger en Tienda', delivery_type: :personal)
    end
  end
end
