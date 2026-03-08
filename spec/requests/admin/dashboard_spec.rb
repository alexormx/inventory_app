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

            it "shows monthly, yearly, and historical net balances based on completed income minus purchases" do
        sign_in admin

        customer = create(:user)
         current_month_date = Date.current
         current_year_date = Date.current.beginning_of_year + 10.days
         previous_year_date = Date.current.prev_year.beginning_of_year + 10.days

         month_sale_order = create(:sale_order,
                    user: customer,
                    status: 'Confirmed',
                    order_date: current_month_date,
                    subtotal: 100,
                    tax_rate: 0,
                    total_tax: 0,
                    total_order_value: 100)
        create(:payment,
           sale_order: month_sale_order,
               amount: 100,
           payment_method: 'tarjeta_de_credito',
           status: 'Completed',
           paid_at: current_month_date)

         year_sale_order = create(:sale_order,
                   user: customer,
                   status: 'Confirmed',
                   order_date: current_year_date,
                   subtotal: 200,
                   tax_rate: 0,
                   total_tax: 0,
                   total_order_value: 200)
         create(:payment,
           sale_order: year_sale_order,
           amount: 200,
           payment_method: 'transferencia_bancaria',
           status: 'Completed',
           paid_at: current_year_date)

         old_sale_order = create(:sale_order,
                  user: customer,
                  status: 'Confirmed',
                  order_date: previous_year_date,
                  subtotal: 300,
                  tax_rate: 0,
                  total_tax: 0,
                  total_order_value: 300)
         create(:payment,
           sale_order: old_sale_order,
           amount: 300,
           payment_method: 'efectivo',
           status: 'Completed',
           paid_at: previous_year_date)

        create(:purchase_order,
               total_order_cost: 40,
               total_cost_mxn: 40,
               subtotal: 40,
               status: 'Pending',
           order_date: current_month_date,
               expected_delivery_date: Date.current + 5.days)

         create(:purchase_order,
           total_order_cost: 50,
           total_cost_mxn: 50,
           subtotal: 50,
           status: 'Delivered',
           order_date: current_year_date,
           expected_delivery_date: current_year_date + 5.days)

         create(:purchase_order,
           total_order_cost: 80,
           total_cost_mxn: 80,
           subtotal: 80,
           status: 'Delivered',
           order_date: previous_year_date,
           expected_delivery_date: previous_year_date + 5.days)

        get admin_dashboard_path

        expect(response).to have_http_status(:success)
         expect(response.body).to include('Balance Mes Actual')
         expect(response.body).to include('Balance Año Actual')
         expect(response.body).to include('Balance Histórico')
        expect(response.body).to include('$ 60.00')
         expect(response.body).to include('$ 210.00')
         expect(response.body).to include('$ 430.00')
         expect(response.body).to include('Ingresos: $ 100.00 · Egresos: $ 40.00')
         expect(response.body).to include('Ingresos: $ 300.00 · Egresos: $ 90.00')
         expect(response.body).to include('Ingresos: $ 600.00 · Egresos: $ 170.00')
      end

      it "shows accurate recurring customers semantics and clarifies conversion baseline" do
        target_year = 2200 + SecureRandom.random_number(200)

        travel_to(Time.zone.local(target_year, 5, 15, 12, 0, 0)) do
          sign_in admin

          repeat_customer = create(:user)
          one_time_customer = create(:user)

          create(:sale_order, user: repeat_customer, status: 'Confirmed', order_date: Date.current.prev_year, subtotal: 90, tax_rate: 0, total_tax: 0, total_order_value: 90)
          create(:sale_order, user: repeat_customer, status: 'Confirmed', order_date: Date.current, subtotal: 120, tax_rate: 0, total_tax: 0, total_order_value: 120)
          create(:sale_order, user: one_time_customer, status: 'Confirmed', order_date: Date.current, subtotal: 80, tax_rate: 0, total_tax: 0, total_order_value: 80)

          allow(VisitorLog).to receive(:sum).with(:visit_count).and_return(40)

          get admin_dashboard_path

          expect(response).to have_http_status(:success)
          expect(response.body).to include('50.0%')
          expect(response.body).to include('1 de 2 clientes activos')
          expect(response.body).to include('Base acumulada:')
          expect(response.body).to include('40 visitas registradas')
        end
      end

      it "shows a custom period badge when filtering by range" do
        sign_in admin

        get admin_dashboard_path, params: { range: 'custom', start_date: '2026-01-01', end_date: '2026-01-31' }

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Personalizado 01/01/2026–31/01/2026')
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
