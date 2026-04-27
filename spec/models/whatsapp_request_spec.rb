require 'rails_helper'

RSpec.describe WhatsappRequest, type: :model do
  describe '#mark_sent!' do
    it 'generates a year-prefixed code, sets status, and computes total' do
      request = create(:whatsapp_request, customer_name: 'Ana')
      product = create(:product, skip_seed_inventory: true, selling_price: 200)
      create(:whatsapp_request_item, whatsapp_request: request, product: product, quantity: 2, unit_price_snapshot: 200)

      request.mark_sent!
      year = Date.current.year

      expect(request.code).to match(/\AWA-#{year}-\d{4}\z/)
      expect(request.status).to eq('sent')
      expect(request.sent_at).to be_present
      expect(request.total_estimate).to eq(400)
    end

    it 'increments code sequence per year' do
      product = create(:product, skip_seed_inventory: true, selling_price: 100)

      first = create(:whatsapp_request, customer_name: 'A')
      create(:whatsapp_request_item, whatsapp_request: first, product: product, quantity: 1, unit_price_snapshot: 100)
      first.mark_sent!

      second = create(:whatsapp_request, customer_name: 'B')
      create(:whatsapp_request_item, whatsapp_request: second, product: product, quantity: 1, unit_price_snapshot: 100)
      second.mark_sent!

      year = Date.current.year
      expect(first.code).to eq("WA-#{year}-0001")
      expect(second.code).to eq("WA-#{year}-0002")
    end
  end

  describe '#whatsapp_message_body' do
    it 'lists code, items and total' do
      product = create(:product, skip_seed_inventory: true, supplier_product_code: 'TKT123', product_name: 'Honda CB1000F', selling_price: 408)
      request = create(:whatsapp_request, customer_name: 'Ana', customer_notes: 'Llega antes del 15')
      create(:whatsapp_request_item, whatsapp_request: request, product: product, quantity: 2, unit_price_snapshot: 408)
      request.mark_sent!

      body = request.whatsapp_message_body

      expect(body).to include(request.code)
      expect(body).to include('TKT123')
      expect(body).to include('Honda CB1000F')
      expect(body).to include('qty 2')
      expect(body).to include('Llega antes del 15')
    end
  end
end
