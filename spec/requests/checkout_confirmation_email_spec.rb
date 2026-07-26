# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkout confirmation email", type: :request do
  let(:user) { create(:user) }
  let(:product) { create(:product, selling_price: 100.00) }
  let(:address) { create(:shipping_address, user: user, default: true) }
  let!(:shipping_method) { create(:shipping_method, :standard) }
  let!(:payment_method) { create(:payment_method, :transferencia_bancaria) }

  before do
    sign_in user
    setup_checkout
  end

  def setup_checkout
    post cart_items_path, params: { product_id: product.id, quantity: 1 }
    post checkout_step2_path, params: {
      selected_address_id: address.id,
      shipping_method: shipping_method.code
    }
    get checkout_step3_path
    @checkout_token = session[:checkout_token]
  end

  def submit_checkout
    post checkout_complete_path, params: {
      payment_method: payment_method.code,
      checkout_token: @checkout_token,
      accept_pending: "1"
    }
  end

  it "enqueues exactly one confirmation after a successful new checkout" do
    expect { submit_checkout }
      .to have_enqueued_mail(OrderConfirmationMailer, :order_confirmation).once

    order = SaleOrder.find_by!(user: user, idempotency_key: @checkout_token)
    expect(response).to redirect_to(checkout_thank_you_path(order_id: order.id))
  end

  it "does not enqueue when Payment creation rolls back" do
    allow_any_instance_of(Payment).to receive(:save!).and_raise(
      ActiveRecord::RecordInvalid.new(Payment.new)
    )

    expect { submit_checkout }
      .not_to have_enqueued_mail(OrderConfirmationMailer, :order_confirmation)
    expect(SaleOrder.where(user: user)).to be_empty
  end

  it "does not enqueue when inventory reservation fails" do
    allow(InventoryServices::ReserveSaleOrderItem).to receive(:call).and_raise(
      InventoryServices::ReserveSaleOrderItem::InsufficientInventory,
      "Inventario insuficiente"
    )

    expect { submit_checkout }.not_to have_enqueued_mail(OrderConfirmationMailer, :order_confirmation)
    expect(SaleOrder.where(user: user)).to be_empty
  end

  it "does not enqueue a second email for a sequential duplicate submission" do
    expect { submit_checkout }
      .to have_enqueued_mail(OrderConfirmationMailer, :order_confirmation).once

    expect { submit_checkout }
      .not_to have_enqueued_mail(OrderConfirmationMailer, :order_confirmation)
  end

  it "does not enqueue during concurrent duplicate recovery" do
    allow_any_instance_of(Checkout::CreateOrder).to receive(:call) do
      create(:sale_order, user: user, idempotency_key: @checkout_token)
      raise ActiveRecord::RecordNotUnique, "duplicate checkout"
    end

    expect { submit_checkout }
      .not_to have_enqueued_mail(OrderConfirmationMailer, :order_confirmation)

    expect(response).to redirect_to(
      checkout_thank_you_path(
        order_id: SaleOrder.find_by!(user: user, idempotency_key: @checkout_token).id
      )
    )
  end

  it "keeps the committed order when enqueueing fails" do
    delivery = instance_double(ActionMailer::MessageDelivery)
    allow(OrderConfirmationMailer).to receive(:order_confirmation).and_return(delivery)
    allow(delivery).to receive(:deliver_later).and_raise(StandardError, "queue unavailable")

    expect { submit_checkout }.not_to raise_error

    order = SaleOrder.find_by!(user: user, idempotency_key: @checkout_token)
    expect(response).to redirect_to(checkout_thank_you_path(order_id: order.id))
  end
end
