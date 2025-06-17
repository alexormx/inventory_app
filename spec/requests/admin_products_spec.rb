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
      patch activate_admin_product_path(product)
      expect(response).to redirect_to(admin_products_path)
      expect(product.reload.status).to eq("active")
    end
  end
end