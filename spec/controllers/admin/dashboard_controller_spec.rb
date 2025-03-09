require 'rails_helper'

RSpec.describe Admin::DashboardController, type: :controller do
  before do
    # Asegúrate de que Devise esté configurado correctamente en el entorno de pruebas
    Rails.application.reload_routes!
  end

  describe "GET #index" do
    context "when admin is logged in" do
      let(:user) { create(:user, :admin) }
 
      before do
        @request.env["devise.mapping"] = Devise.mappings[:user]
        sign_in user
        get :index, params: { use_route: :admin_dashboard }
      end
      
      it "returns http success" do
        expect(response).to have_http_status(:success)
      end

      it "routes to index" do
        expect(get: "/admin/dashboard").to route_to(controller: "admin/dashboard", action: "index")
      end
    end

    context "when non-admin user" do
      let(:user) { create(:user, role: 'customer') }

      before do
        @request.env["devise.mapping"] = Devise.mappings[:user] # Explicitly set the mapping
        sign_in user
        get :index
      end

      it "redirects to root with alert" do
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Not authorized.")
      end
    end

    context "when not logged in" do
      it "redirects to login page" do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end