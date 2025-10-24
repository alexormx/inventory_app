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
        unit_cost: 50.0,
        total_line_cost: 100.0
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

      it 'includes product SKU' do
        expect(mail.html_part.body.encoded).to include(product.product_sku)
        expect(mail.text_part.body.encoded).to include(product.product_sku)
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
  end
end
