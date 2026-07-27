# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Orders summary', type: :request do
  let(:user) { create(:user, password: 'password123', password_confirmation: 'password123') }

  it 'renders summary page with raw path' do
    sign_in user
    order = create(:sale_order, user: user)
    get summary_order_path(order), headers: { 'ACCEPT' => 'text/html' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order.id.to_s)
  end

  it 'uses persisted discount, tax, shipping, total, balance, and shipping snapshot' do
    sign_in user
    order = create(
      :sale_order,
      user: user,
      subtotal: 100,
      tax_rate: 10,
      discount: 5,
      shipping_cost: 20
    )
    create(:sale_order_item, sale_order: order, quantity: 1, unit_final_price: 100, total_line_cost: 100)
    create(
      :order_shipping_address,
      sale_order: order,
      shipping_method: 'envio_estandar',
      raw_address_json: { 'shipping_method_name' => 'Envío estándar confirmado' }
    )
    create(:payment, sale_order: order, amount: 50, status: 'Completed')

    get summary_order_path(order)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Descuento', 'Impuestos', 'Envío estándar confirmado', 'Aún no enviado')
    expect(response.body).to include('$5.00', '$10.00', '$20.00', '$125.00', '$50.00', '$75.00')
    expect(response.body).not_to include('Aún no se ha seleccionado un método de entrega')
  end
end
