require 'rails_helper'

RSpec.describe "Admin::Dashboard", type: :request do
  let(:user) { create(:user, role: :admin) }

  before do
    sign_in user
  end

  describe "GET /admin/dashboard" do
    it "returns http success" do
      get admin_dashboard_path
      expect(response).to have_http_status(:success)
    end
  end
end
