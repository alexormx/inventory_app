# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Payment received email', type: :model do
  let(:user) { create(:user, name: 'Ana López') }

  def order(idempotency_key: SecureRandom.hex(8))
    create(:sale_order, user: user, status: 'Pending', total_order_value: 100, idempotency_key: idempotency_key)
  end

  def pending_payment(sale_order, amount: 100)
    sale_order.payments.create!(amount: amount, payment_method: :transferencia_bancaria, status: 'Pending')
  end

  it 'tells an online customer once the payment confirms the order' do
    sale_order = order
    payment = pending_payment(sale_order)

    expect { payment.update!(status: 'Completed') }
      .to have_enqueued_mail(OrderConfirmationMailer, :payment_confirmation).with(sale_order).once
    expect(sale_order.reload.status).to eq('Confirmed')
  end

  it 'waits until the order is fully paid' do
    sale_order = order
    payment = pending_payment(sale_order, amount: 40)

    expect { payment.update!(status: 'Completed') }
      .not_to have_enqueued_mail(OrderConfirmationMailer, :payment_confirmation)
  end

  it 'does not email for orders captured by the admin' do
    sale_order = order(idempotency_key: nil)
    payment = pending_payment(sale_order)

    expect { payment.update!(status: 'Completed') }
      .not_to have_enqueued_mail(OrderConfirmationMailer, :payment_confirmation)
  end

  it 'does not repeat the email when an already confirmed order gets another payment' do
    sale_order = order
    pending_payment(sale_order).update!(status: 'Completed')

    expect { sale_order.payments.create!(amount: 10, payment_method: :efectivo, status: 'Completed') }
      .not_to have_enqueued_mail(OrderConfirmationMailer, :payment_confirmation)
  end
end
