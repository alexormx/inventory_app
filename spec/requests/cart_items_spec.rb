require 'rails_helper'

RSpec.describe "CartItems", type: :request do
  let!(:product) { create(:product) }

  describe "POST /cart_items" do
    it "adds item to the cart with brand_new condition" do
      post cart_items_path, params: { product_id: product.id }
      expect(session[:cart][product.id.to_s]).to be_a(Hash)
      expect(session[:cart][product.id.to_s]['brand_new']).to eq(1)
    end

    it "adds item with specific condition" do
      # Crear inventario disponible con condición misb
      create(:inventory, product: product, status: :available, item_condition: :misb)
      post cart_items_path, params: { product_id: product.id, condition: 'misb' }
      expect(session[:cart][product.id.to_s]['misb']).to eq(1)
    end
  end

  describe "PUT /cart_items/:id" do
    before { post cart_items_path, params: { product_id: product.id } }

    it "updates quantity for condition" do
      put cart_item_path(product), params: { product_id: product.id, quantity: 3, condition: 'brand_new' }
      expect(session[:cart][product.id.to_s]['brand_new']).to eq(3)
    end

    it "returns json with totals" do
      put cart_item_path(product),
          params: { product_id: product.id, quantity: 2, condition: 'brand_new' },
          headers: { "ACCEPT" => "application/json" }

      json = JSON.parse(response.body)
      expect(json["quantity"]).to eq(2)
      expect(json["cart_total"]).to be_present
      expect(json["total_items"]).to eq(2)
    end
  end

  describe "DELETE /cart_items/:id" do
    before { post cart_items_path, params: { product_id: product.id } }

    it "removes item condition" do
      delete cart_item_path(product), params: { product_id: product.id, condition: 'brand_new' }
      expect(session[:cart][product.id.to_s]).to be_nil
    end

    it "returns json after delete" do
      delete cart_item_path(product),
             params: { product_id: product.id, condition: 'brand_new' },
             headers: { "ACCEPT" => "application/json" }

      json = JSON.parse(response.body)
      expect(json["cart_total"]).to be_present
      expect(json["total_items"]).to eq(0)
    end
  end
end