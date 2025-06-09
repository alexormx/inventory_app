require 'rails_helper'

RSpec.describe CartItemsController, type: :controller do
  let!(:product) { create(:product) }

  describe "POST #add_to_cart" do
    it "adds a product to the cart" do
      post :add_to_cart, params: { product_id: product.id }, session: {}
      expect(session[:cart][product.id.to_s]).to eq(1)
    end
  end

  describe "DELETE #remove_from_cart" do
    it "removes a product from the cart" do
      session[:cart] = { product.id.to_s => 1 }
      delete :remove_from_cart, params: { product_id: product.id }
      expect(session[:cart][product.id.to_s]).to be_nil
    end
  end

  describe "GET #show" do
    it "renders the cart page" do
      get :show
      expect(response).to have_http_status(:success)
    end
  end
end
