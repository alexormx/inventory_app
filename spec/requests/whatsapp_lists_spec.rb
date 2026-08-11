require 'rails_helper'

RSpec.describe 'WhatsApp Lists', type: :request do
  before(:all) { Rails.application.reload_routes! }
  let(:product) { create(:product, selling_price: 250, status: :active, seed_inventory_count: 3) }

  describe 'POST /whatsapp-list/items' do
    it 'creates a draft request and adds the product as guest' do
      expect {
        post whatsapp_list_items_path, params: { product_id: product.id }, headers: { 'Accept' => 'text/html' }
      }.to change(WhatsappRequest, :count).by(1)
        .and change(WhatsappRequestItem, :count).by(1)

      request = WhatsappRequest.last
      expect(request.status).to eq('draft')
      expect(request.session_token).to be_present
      expect(request.whatsapp_request_items.first.product).to eq(product)
      expect(request.whatsapp_request_items.first.unit_price_snapshot).to eq(250)
    end

    it 'increments quantity when the same product is added twice' do
      post whatsapp_list_items_path, params: { product_id: product.id }, headers: { 'Accept' => 'text/html' }
      post whatsapp_list_items_path, params: { product_id: product.id }, headers: { 'Accept' => 'text/html' }

      expect(WhatsappRequest.count).to eq(1)
      expect(WhatsappRequestItem.count).to eq(1)
      expect(WhatsappRequestItem.last.quantity).to eq(2)
    end

    context 'sin stock y sin preorder/backorder' do
      let(:product) { create(:product, skip_seed_inventory: true, selling_price: 250, status: :active) }

      it 'no agrega el producto' do
        expect {
          post whatsapp_list_items_path, params: { product_id: product.id }, headers: { 'Accept' => 'text/html' }
        }.not_to change(WhatsappRequestItem, :count)
      end
    end

    context 'con inventario físico sin verificar' do
      let(:product) { create(:product, skip_seed_inventory: true, selling_price: 250, status: :active) }

      before do
        create(:inventory, product: product, status: :available, inventory_location: nil)
        product.update_columns(status: 'active', auto_paused: false, auto_paused_at: nil)
      end

      it 'no permite pedir usando available sin ubicación' do
        expect do
          post whatsapp_list_items_path,
               params: { product_id: product.id },
               headers: { 'Accept' => 'text/html' }
        end.not_to change(WhatsappRequestItem, :count)
      end
    end

    context 'con inventario on-hand confirmado' do
      let(:product) { create(:product, skip_seed_inventory: true, selling_price: 250, status: :active) }
      let(:location) { create(:inventory_location, :warehouse) }

      before do
        create(:inventory, product: product, status: :available, inventory_location: location)
        create(:inventory, product: product, status: :available, inventory_location: nil)
      end

      it 'permite la cantidad localizada pero no aumenta el límite con la pieza sin ubicación' do
        post whatsapp_list_items_path,
             params: { product_id: product.id, quantity: 1 },
             headers: { 'Accept' => 'text/html' }

        expect(WhatsappRequestItem.last.quantity).to eq(1)

        post whatsapp_list_items_path,
             params: { product_id: product.id, quantity: 1 },
             headers: { 'Accept' => 'text/html' }

        expect(WhatsappRequestItem.last.quantity).to eq(1)
      end
    end

    context 'con inventario legítimo en tránsito' do
      let(:product) { create(:product, skip_seed_inventory: true, selling_price: 250, status: :active) }

      before do
        create(:inventory, product: product, status: :in_transit, item_condition: :brand_new)
      end

      it 'mantiene la unidad en tránsito como ordenable' do
        expect do
          post whatsapp_list_items_path,
               params: { product_id: product.id },
               headers: { 'Accept' => 'text/html' }
        end.to change(WhatsappRequestItem, :count).by(1)
      end
    end

    context 'con available ya ligado a una orden' do
      let(:product) { create(:product, skip_seed_inventory: true, selling_price: 250, status: :active) }
      let(:location) { create(:inventory_location, :warehouse) }

      before do
        inventory = create(:inventory, product: product, status: :available, inventory_location: location)
        inventory.update_columns(sale_order_id: create(:sale_order).id)
      end

      it 'no lo cuenta como stock libre' do
        expect do
          post whatsapp_list_items_path,
               params: { product_id: product.id },
               headers: { 'Accept' => 'text/html' }
        end.not_to change(WhatsappRequestItem, :count)
      end
    end

    context 'producto preorderable sin stock' do
      let(:product) do
        create(:product, skip_seed_inventory: true, selling_price: 250, status: :active, preorder_available: true)
      end

      it 'permite agregarlo (oversell_allowed)' do
        expect {
          post whatsapp_list_items_path, params: { product_id: product.id }, headers: { 'Accept' => 'text/html' }
        }.to change(WhatsappRequestItem, :count).by(1)
      end
    end

    context 'al exceder el límite por producto' do
      it 'rechaza agregar más del máximo permitido' do
        Cart::MAX_NEW_ITEMS_PER_PRODUCT.times do
          post whatsapp_list_items_path, params: { product_id: product.id }, headers: { 'Accept' => 'text/html' }
        end
        expect(WhatsappRequestItem.last.quantity).to eq(Cart::MAX_NEW_ITEMS_PER_PRODUCT)

        post whatsapp_list_items_path, params: { product_id: product.id }, headers: { 'Accept' => 'text/html' }
        expect(WhatsappRequestItem.last.quantity).to eq(Cart::MAX_NEW_ITEMS_PER_PRODUCT)
      end
    end
  end

  describe 'POST /whatsapp-list/send' do
    before { SiteSetting.set('whatsapp_orders_phone', '5215555555555') }

    it 'requires customer_name and stays on the page if missing' do
      post whatsapp_list_items_path, params: { product_id: product.id }, headers: { 'Accept' => 'text/html' }
      post send_whatsapp_list_path, params: { whatsapp_request: { customer_name: '' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(WhatsappRequest.last.status).to eq('draft')
    end

    it 'marks request as sent and redirects to wa.me URL when valid' do
      post whatsapp_list_items_path, params: { product_id: product.id }, headers: { 'Accept' => 'text/html' }
      post send_whatsapp_list_path, params: { whatsapp_request: { customer_name: 'Ana López' } }

      expect(response).to redirect_to(/wa\.me\/5215555555555/)
      request = WhatsappRequest.last
      expect(request.status).to eq('sent')
      expect(request.code).to match(/\AWA-\d{4}-\d{4}\z/)
    end
  end
end
