require 'rails_helper'

RSpec.describe Admin::PaymentsController, type: :controller do
  let(:admin) { create(:user, :admin) }
  let(:sale_order) { create(:sale_order) }

  before { sign_in admin }

  describe 'POST create' do
    it 'creates a new payment for the sale order' do
      expect {
        post :create, params: { sale_order_id: sale_order.id, payment: { amount: 50.0, payment_method: 'efectivo', status: 'Completed' } }
      }.to change(Payment, :count).by(1)

      expect(Payment.last.sale_order).to eq(sale_order)
    end
  end
end
