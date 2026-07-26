# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OrderConfirmationMailer, type: :mailer do
  describe '#order_confirmation' do
    let(:user) { create(:user, email: 'customer@example.com') }
    let(:product) { create(:product, product_name: 'Test Product', product_sku: 'TEST-001', selling_price: 50.0) }
    let(:address) { create(:shipping_address, user: user, city: 'Mexico City') }

    let(:sale_order) do
      create(:sale_order,
        user: user,
        subtotal: 100.0,
        shipping_cost: 10.0,
        total_tax: 0.0,
        total_order_value: 110.0,
        notes: 'Test order notes',
        status: 'Pending'
      )
    end

    let(:sale_order_item) do
      create(:sale_order_item,
        sale_order: sale_order,
        product: product,
        quantity: 2,
        unit_cost: 20.0,
        unit_selling_price: 50.0,
        unit_final_price: 50.0,
        total_line_cost: 100.0
      )
    end

    let(:payment) do
      create(
        :payment,
        sale_order: sale_order,
        amount: 110.0,
        payment_method: "transferencia_bancaria",
        status: "Pending"
      )
    end

    let(:order_shipping_address) do
      create(:order_shipping_address,
        sale_order: sale_order,
        full_name: address.full_name,
        line1: address.line1,
        line2: address.line2,
        city: address.city,
        state: address.state,
        postal_code: address.postal_code,
        country: address.country
      )
    end

    let(:mail) do
      sale_order_item # Ensure item exists
      order_shipping_address # Ensure address exists
      payment # Ensure persisted Payment exists
      OrderConfirmationMailer.order_confirmation(sale_order)
    end

    describe 'email headers' do
      it 'renders the headers' do
        expect(mail.subject).to eq("Confirmación de Pedido ##{sale_order.id} - Pasatiempos")
        expect(mail.to).to eq([user.email])
        expect(mail.from).to eq(['soporte@pasatiempos.com.mx'])
      end
    end

    describe 'email body' do
      it 'includes order ID in HTML body' do
        expect(mail.html_part.body.encoded).to include("Pedido ##{sale_order.id}")
      end

      it 'includes order ID in text body' do
        expect(mail.text_part.body.encoded).to include("PEDIDO ##{sale_order.id}")
      end

      it 'includes product name in HTML body' do
        expect(mail.html_part.body.encoded).to include(product.product_name)
      end

      it 'includes product name in text body' do
        expect(mail.text_part.body.encoded).to include(product.product_name)
      end

      it 'never exposes the product SKU (supplier identifier)' do
        expect(mail.html_part.body.encoded).not_to include(product.product_sku)
        expect(mail.text_part.body.encoded).not_to include(product.product_sku)
      end

      it 'includes quantity and prices' do
        expect(mail.html_part.body.encoded).to include('2')
        expect(mail.html_part.body.encoded).to include('$50.00')
        expect(mail.html_part.body.encoded).to include('$100.00')
      end

      it 'includes order totals' do
        expect(mail.html_part.body.encoded).to include('$110.00')
        expect(mail.text_part.body.encoded).to include('$110.00')
      end

      it 'uses persisted customer prices and Payment data without current payment settings' do
        create(
          :payment_method,
          code: "transferencia_bancaria",
          account_number: "PLACEHOLDER-ACCOUNT-NUMBER",
          instructions: "PLACEHOLDER-INSTRUCTIONS"
        )
        product.update!(selling_price: 999.0)

        html = mail.html_part.body.decoded
        text = mail.text_part.body.decoded

        expect(html).to include('$50.00', '$100.00', '$110.00')
        expect(text).to include('$50.00', '$100.00', '$110.00')
        expect(html).to include('Transferencia bancaria', 'pendiente')
        expect(html).not_to include('$20.00', '$999.00', 'PLACEHOLDER')
        expect(text).not_to include('$20.00', '$999.00', 'PLACEHOLDER')
      end

      it 'includes shipping address' do
        expect(mail.html_part.body.encoded).to include(order_shipping_address.full_name)
        expect(mail.html_part.body.encoded).to include(address.city)
        expect(mail.text_part.body.encoded).to include(order_shipping_address.full_name)
      end

      it 'includes order notes when present' do
        expect(mail.html_part.body.encoded).to include(sale_order.notes)
        expect(mail.text_part.body.encoded).to include(sale_order.notes)
      end

      it 'includes user email' do
        expect(mail.html_part.body.encoded).to include(user.email)
        expect(mail.text_part.body.encoded).to include(user.email)
      end
    end

    describe 'with preorder items' do
      let(:sale_order_item_with_preorder) do
        create(:sale_order_item,
          sale_order: sale_order,
          product: product,
          quantity: 5,
          unit_cost: 50.0,
          total_line_cost: 250.0,
          preorder_quantity: 3
        )
      end

      let(:mail_with_preorder) do
        sale_order_item_with_preorder
        order_shipping_address
        OrderConfirmationMailer.order_confirmation(sale_order)
      end

      it 'mentions preorder quantity' do
        expect(mail_with_preorder.html_part.body.encoded).to include('preventa')
        expect(mail_with_preorder.html_part.body.encoded).to include('3')
      end
    end

    describe 'with backorder items' do
      let(:sale_order_item_with_backorder) do
        create(:sale_order_item,
          sale_order: sale_order,
          product: product,
          quantity: 5,
          unit_cost: 50.0,
          total_line_cost: 250.0,
          backordered_quantity: 2
        )
      end

      let(:mail_with_backorder) do
        sale_order_item_with_backorder
        order_shipping_address
        OrderConfirmationMailer.order_confirmation(sale_order)
      end

      it 'mentions backorder quantity' do
        expect(mail_with_backorder.html_part.body.encoded).to include('backorder')
        expect(mail_with_backorder.html_part.body.encoded).to include('2')
      end
    end

    describe 'delivery' do
      it 'sends an email' do
        expect { mail.deliver_now }.to change { ActionMailer::Base.deliveries.count }.by(1)
      end

      it 'sends to the correct recipient' do
        mail.deliver_now
        expect(ActionMailer::Base.deliveries.last.to).to include(user.email)
      end
    end

    context 'when optional address, payment, notes, and line prices are missing' do
      let(:minimal_order) { create(:sale_order, user: user, shipping_cost: 0, notes: nil) }

      before do
        item = create(
          :sale_order_item,
          sale_order: minimal_order,
          product: product,
          unit_cost: 20.0,
          unit_selling_price: 50.0,
          unit_final_price: 50.0,
          total_line_cost: 50.0
        )
        item.update_columns(unit_selling_price: nil, unit_final_price: nil, total_line_cost: nil)
      end

      it 'renders both parts without exposing placeholder payment details' do
        minimal_mail = OrderConfirmationMailer.order_confirmation(minimal_order)

        expect { minimal_mail.html_part.body.decoded }.not_to raise_error
        expect { minimal_mail.text_part.body.decoded }.not_to raise_error
        expect(minimal_mail.html_part.body.decoded).not_to include('PLACEHOLDER')
        expect(minimal_mail.text_part.body.decoded).not_to include('PLACEHOLDER')
      end
    end
  end
end
