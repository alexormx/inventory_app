require 'rails_helper'

RSpec.describe "CartItems", type: :request do
  let!(:product) { create(:product) }

  describe "POST /cart_items" do
    it "adds item to the cart" do
      post cart_items_path, params: { product_id: product.id }
      expect(session[:cart][product.id.to_s]).to eq(1)
    end
  end

  describe "PUT /cart_items/:id" do
    before { post cart_items_path, params: { product_id: product.id } }

    it "updates quantity" do
      put cart_item_path(product), params: { product_id: product.id, quantity: 3 }
      expect(session[:cart][product.id.to_s]).to eq(3)
    end
  end

  describe "DELETE /cart_items/:id" do
    before { post cart_items_path, params: { product_id: product.id } }

    it "removes item" do
      delete cart_item_path(product), params: { product_id: product.id }
      expect(session[:cart]).to be_empty
    end
  end
end