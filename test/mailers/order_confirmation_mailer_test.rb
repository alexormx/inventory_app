# frozen_string_literal: true

require 'test_helper'

class OrderConfirmationMailerTest < ActionMailer::TestCase
  test 'order_confirmation' do
    user = User.create!(email: 'mailer-minitest@example.com', password: 'password123', role: 'customer', confirmed_at: Time.current)
    order = SaleOrder.create!(user: user, order_date: Date.current, subtotal: 0, tax_rate: 0,
                              total_tax: 0, total_order_value: 0, status: 'Pending')

    mail = OrderConfirmationMailer.order_confirmation(order)

    assert_equal "Confirmación de Pedido ##{order.id} - Pasatiempos", mail.subject
    assert_equal [user.email], mail.to
    assert_equal ['soporte@pasatiempos.com.mx'], mail.from
    assert_includes mail.html_part.body.decoded, "Pedido ##{order.id}"
    assert_equal 1, mail.html_part.body.decoded.scan(/<html\b/i).length
    assert_includes mail.text_part.body.decoded, "PEDIDO ##{order.id}"
  end
end
