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
