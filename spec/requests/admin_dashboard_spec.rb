require 'rails_helper'

RSpec.describe "Admin::Dashboard", type: :request do
  let(:user) { create(:user, email: "user@example.com", password: "password123", role: :admin) }

  before do
    sign_in user  # Ensure authentication
  end

  describe "GET /admin/dashboard" do
    it "returns http success" do
      get admin_dashboard_path
      expect(response).to have_http_status(:success)
    end
  end
end
