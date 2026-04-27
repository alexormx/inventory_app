FactoryBot.define do
  factory :whatsapp_request do
    status { :draft }
    session_token { SecureRandom.urlsafe_base64(24) }
    customer_name { 'Cliente Prueba' }
  end

  factory :whatsapp_request_item do
    whatsapp_request
    product
    quantity { 1 }
    unit_price_snapshot { 100.0 }
  end
end
