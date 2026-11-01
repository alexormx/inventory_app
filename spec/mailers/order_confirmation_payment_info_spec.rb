# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OrderConfirmationMailer, 'payment instructions' do
  let(:order) { create(:sale_order, total_order_value: 350, subtotal: 350) }

  it 'includes the bank details for a pending transfer' do
    create(:payment_method, :transferencia_bancaria)
    create(:payment, sale_order: order, amount: 350, payment_method: 'transferencia_bancaria', status: 'Pending')

    body = described_class.order_confirmation(order).html_part.body.to_s

    expect(body).to include('012345678901234567', 'BBVA', 'Pasatiempos SA de CV', order.id)
  end

  it 'links Mercado Pago orders to their order page to pay' do
    create(:payment, sale_order: order, amount: 350, payment_method: 'mercado_pago', status: 'Pending')

    body = described_class.order_confirmation(order).html_part.body.to_s

    expect(body).to include('Completa tu pago con Mercado Pago', "/orders/#{order.id}")
  end

  it 'sends the OXXO/SPEI ticket link' do
    create(:payment, sale_order: order, amount: 350, payment_method: 'mercado_pago', status: 'Pending',
                     provider_ticket_url: 'https://www.mercadopago.com.mx/payments/1/ticket')

    mail = described_class.mercado_pago_ticket(order)

    expect(mail.subject).to include('Ficha de pago')
    expect(mail.html_part.body.to_s).to include('https://www.mercadopago.com.mx/payments/1/ticket', '$350.00')
  end

  it 'renders the logo at a fixed small size' do
    create(:payment, sale_order: order, amount: 350, payment_method: 'efectivo', status: 'Pending')

    body = described_class.order_confirmation(order).html_part.body.to_s

    logo = body[/<img[^>]*logo\.png[^>]*>/]
    expect(logo).to include('width="64"', 'height="64"')
  end
end
