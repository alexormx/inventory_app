require 'rails_helper'

RSpec.describe "Admin::Products", type: :request do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: :admin) }
  let!(:product) { create(:product) }

  before do
    login_as(admin, scope: :user)
  end

  describe "PATCH /admin/products/:id/activate" do
    it "activates the product using its slug" do
  patch activate_admin_product_path(product) # HTML request (no turbo stream)
  expect(response).to have_http_status(302)
      expect(product.reload.status).to eq("active")
    end
  end
end