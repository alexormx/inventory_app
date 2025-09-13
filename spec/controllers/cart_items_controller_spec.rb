require 'rails_helper'

RSpec.describe CartItemsController, type: :controller do
  let!(:product) { create(:product, status: :active) }
  let(:user) { create(:user, confirmed_at: Time.current) }

  before do
    sign_in user
    session[:cart] = {}
  end

  describe "POST #create" do
    it "adds a product to the cart" do
      post :create, params: { product_id: product.id }
      expect(session[:cart]).to be_present
      expect(session[:cart][product.id.to_s]).to eq(1)
    end
  end

  describe "DELETE #destroy" do
    it "removes a product from the cart" do
      session[:cart] = { product.id.to_s => 1 }
      delete :destroy, params: { id: product.id, product_id: product.id }
      expect(session[:cart][product.id.to_s]).to be_nil
    end
  end
end