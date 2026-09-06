# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Customer profile', type: :request do
  let(:customer) { create(:user, name: 'Ana Cliente', phone: '5512345678') }

  it 'renders an authenticated customer profile with a saved shipping address' do
    create(:shipping_address, user: customer, full_name: 'Ana Destinataria', line1: 'Calle Roble 123')
    sign_in customer

    get profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Ana Cliente', 'Ana Destinataria', 'Calle Roble 123', 'Principal', '5512345678')
  end

  it 'renders empty states and missing optional contact information' do
    customer.update!(name: nil, phone: nil, address: nil, discount_rate: nil)
    sign_in customer

    get profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Usuario', customer.email, 'Aún no tienes pedidos.',
                                     'No tienes direcciones de envío guardadas.')
  end

  it 'renders optional address lines and identifies only the default address' do
    create(:shipping_address, user: customer, full_name: 'Destino Principal', line2: 'Interior 4')
    create(:shipping_address, user: customer, full_name: 'Destino Secundario', default: false, state: nil)
    sign_in customer

    get profile_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css('h6.card-title .badge').map(&:text)).to eq(['Principal'])
    expect(document.text).to include('Destino Principal', 'Destino Secundario', 'Interior 4', 'Ciudad 12345')
  end

  it 'renders one pending order without a shipment or payment' do
    order = create(:sale_order, user: customer)
    sign_in customer

    get profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order_path(order), order.id)
    expect(order.shipment).to be_nil
    expect(order.payments).to be_empty
  end

  it 'renders multiple orders including a paid and delivered order' do
    pending_order = create(:sale_order, user: customer)
    delivered_order = create(:sale_order, user: customer)
    create(:payment, sale_order: delivered_order, amount: delivered_order.total_order_value)
    shipment = create(:shipment, sale_order: delivered_order)
    shipment.update!(status: :delivered)
    sign_in customer

    get profile_path

    expect(response).to have_http_status(:ok)
    expect(delivered_order.reload.status).to eq('Delivered')
    expect(response.body).to include(order_path(pending_order), order_path(delivered_order))
  end

  it 'renders an order with a payment still pending' do
    order = create(:sale_order, user: customer)
    create(:payment, sale_order: order, status: 'Pending')
    sign_in customer

    get profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order_path(order))
    expect(order.payments.where(status: 'Completed')).to be_empty
  end

  it 'allows a confirmed offline-created customer who has acquired login credentials' do
    legacy = create(:user, created_offline: true, password: nil, password_confirmation: nil,
                           name: nil, phone: nil, address: nil)
    legacy.update!(password: 'claimed-password123', password_confirmation: 'claimed-password123')
    create(:shipping_address, user: legacy)
    post user_session_path, params: { user: { email: legacy.email, password: 'claimed-password123' } }

    get profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(legacy.email, 'John Tester')
  end

  it 'keeps another customer and internal data out of the profile even with substituted IDs' do
    customer.update!(notes: 'PRIVATE-ADMIN-NOTE', tax_id: 'PRIVATE-TAX-ID', api_token: 'PRIVATE-API-TOKEN')
    other = create(:user, name: 'Other Private Customer')
    other_order = create(:sale_order, user: other)
    create(:shipping_address, user: other, full_name: 'PRIVATE-RECIPIENT', line1: 'PRIVATE-STREET')
    create(:payment, sale_order: other_order, amount: 42.37)
    create(:shipment, sale_order: other_order, tracking_number: 'PRIVATE-TRACKING')
    VisitorLog.create!(user: customer, ip_address: '127.0.0.1', path: '/PRIVATE-ACTIVITY')
    sign_in customer

    get profile_path, params: { id: other.id, user_id: other.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(customer.name, 'Aún no tienes pedidos.')
    expect(response.body).not_to include(other.name, other.email, other_order.id, 'PRIVATE-',
                                         '42.37', 'Panel de administración')
  end

  %i[order_path summary_order_path].each do |route|
    it "refuses another customers order through #{route}" do
      other_order = create(:sale_order)
      sign_in customer

      get public_send(route, other_order)

      expect(response).to have_http_status(:not_found)
    end
  end

  it 'updates only the signed-in customers permitted contact fields' do
    other = create(:user, name: 'Other Customer')
    sign_in customer

    get edit_profile_path, params: { id: other.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(other.email)

    patch profile_path, params: { id: other.id, user: { id: other.id, name: 'Updated Name', role: 'admin',
                                                       notes: 'injected', discount_rate: 100 } }

    expect(response).to redirect_to(profile_path)
    expect(customer.reload).to have_attributes(name: 'Updated Name', role: 'customer', notes: nil, discount_rate: 0)
    expect(other.reload.name).to eq('Other Customer')
  end

  it 'requires authentication' do
    get profile_path

    expect(response).to redirect_to(new_user_session_path)
  end
end
