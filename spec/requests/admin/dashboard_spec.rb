require 'rails_helper'

RSpec.describe "Admin Dashboard", type: :request do
  before(:all) { Rails.application.reload_routes! }

  describe "GET /admin/dashboard" do
    context "when admin is logged in" do
      let(:admin) { create(:user, role: :admin) }

      it "returns http success" do
        sign_in admin
        get admin_dashboard_path
        expect(response).to have_http_status(:success)
      end

      # Basic smoke to ensure path helper works
      it "returns success via path helper" do
        sign_in admin
        get admin_dashboard_path
        expect(response).to have_http_status(:success)
      end

      it "shows historical net balance based on completed income minus purchases" do
        sign_in admin

        customer = create(:user)
        sale_order = create(:sale_order,
                            user: customer,
                            status: 'Confirmed',
                            order_date: Date.current,
                            subtotal: 100,
                            tax_rate: 0,
                            total_tax: 0,
                            total_order_value: 100)
        create(:payment,
               sale_order: sale_order,
               amount: 100,
           payment_method: 'tarjeta_de_credito',
               status: 'Completed')

        create(:purchase_order,
               total_order_cost: 40,
               total_cost_mxn: 40,
               subtotal: 40,
               status: 'Pending',
               order_date: Date.current,
               expected_delivery_date: Date.current + 5.days)

        get admin_dashboard_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Balance Neto Histórico')
        expect(response.body).to include('$ 60.00')
        expect(response.body).to include('Ingresos cobrados: $ 100.00')
        expect(response.body).to include('Egresos: $ 40.00')
      end
    end

    context "when non-admin user" do
      let(:user) { create(:user, role: :customer) }

      it "redirects to root with alert" do
        sign_in user
        get admin_dashboard_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        get admin_dashboard_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
