require 'rails_helper'

RSpec.describe Admin::PaymentsController, type: :controller do
  before do
    Rails.application.reload_routes!
  end
  let(:admin) { create(:user, :admin) }
  let(:sale_order) { create(:sale_order) }

  before do
    # Necesario para Devise en controller specs
    @request.env["devise.mapping"] = Devise.mappings[:user]
    # Evitar dependencias de Warden en controller specs (patrón del repo)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:authorize_admin!).and_return(true)
    allow(controller).to receive(:current_user).and_return(admin)
  end

  describe 'POST create' do
    it 'creates a new payment for the sale order' do
      expect {
        post :create, params: { payment: { amount: 50.0, payment_method: 'efectivo', status: 'Completed', sale_order_id: sale_order.id } }
      }.to change(Payment, :count).by(1)

      expect(Payment.last.sale_order).to eq(sale_order)
    end
  end
end
