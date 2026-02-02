require 'rails_helper'

RSpec.describe CartItemsController, type: :controller do
  let!(:product) { create(:product, status: :active) }
  let(:user) { create(:user, confirmed_at: Time.current) }

  before do
    # Evitar filtros de tracking y confirmación complejos: simulamos usuario y sesión
    allow(controller).to receive(:current_user).and_return(user)
    session[:cart] = {}
  end

  describe "POST #create" do
    it "adds a product to the cart with default brand_new condition" do
      post :create, params: { product_id: product.id }
      expect(session[:cart]).to be_present
      expect(session[:cart][product.id.to_s]).to be_a(Hash)
      expect(session[:cart][product.id.to_s]['brand_new']).to eq(1)
    end

    it "adds a product with specific condition" do
      # Crear inventario disponible con condición misb
      create(:inventory, product: product, status: :available, item_condition: :misb)
      post :create, params: { product_id: product.id, condition: 'misb' }
      expect(session[:cart][product.id.to_s]['misb']).to eq(1)
    end
  end

  describe "DELETE #destroy" do
    it "removes a product condition from the cart" do
      session[:cart] = { product.id.to_s => { 'brand_new' => 1 } }
      delete :destroy, params: { id: product.id, product_id: product.id, condition: 'brand_new' }
      expect(session[:cart][product.id.to_s]).to be_nil
    end

    it "removes all conditions when no condition specified" do
      session[:cart] = { product.id.to_s => { 'brand_new' => 2, 'misb' => 1 } }
      delete :destroy, params: { id: product.id, product_id: product.id }
      expect(session[:cart][product.id.to_s]).to be_nil
    end
  end
end