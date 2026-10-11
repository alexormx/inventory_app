# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Vencimiento del carrito', type: :request do
  let(:notice) { ShoppingCarts::SessionCartExpiry::NOTICE }
  # Con su inventario de fábrica el producto queda activo y se puede agregar.
  let(:product) { create(:product, selling_price: 100, minimum_price: 100) }

  context 'cliente con sesión' do
    let(:user) { create(:user) }

    before do
      sign_in user
      post cart_items_path, params: { product_id: product.id }
    end

    def age_cart!(by)
      ShoppingCarts::ActiveCartResolver.find(user).update_columns(last_activity_at: by.ago)
    end

    it 'tras 4 h sin cambios el carrito aparece vacío con el aviso' do
      age_cart!(5.hours)
      get cart_path
      expect(response.body).to include(notice)
      expect(ShoppingCart.where(user: user).pluck(:status)).to eq(['expired'])
      expect(CartInventoryHold.count).to eq(0)
    end

    it 'con actividad reciente no vence ni avisa' do
      age_cart!(3.hours)
      get cart_path
      expect(response.body).not_to include(notice)
      expect(ShoppingCarts::ActiveCartResolver.find(user)).to be_present
    end

    it 'después de vencer, agregar crea un carrito nuevo' do
      age_cart!(5.hours)
      get cart_path
      post cart_items_path, params: { product_id: product.id }
      expect(ShoppingCart.where(user: user).group(:status).count).to eq('expired' => 1, 'active' => 1)
    end

    it 'el checkout no crea orden si el carrito venció y lo explica' do
      age_cart!(5.hours)
      get checkout_step1_path
      expect(response).to redirect_to(cart_path)
      expect(flash[:warning]).to eq(notice)
      expect(SaleOrder.count).to eq(0)
    end
  end

  context 'visitante' do
    it 'el carrito de sesión vence a las 4 h del último cambio' do
      post cart_items_path, params: { product_id: product.id }
      travel 5.hours do
        get cart_path
        expect(response.body).to include(notice)
        expect(session[:cart]).to be_blank
      end
    end

    it 'un carrito de visitante vencido no se importa al iniciar sesión' do
      post cart_items_path, params: { product_id: product.id }
      travel 5.hours do
        sign_in create(:user)
        get cart_path
        expect(ShoppingCartItem.count).to eq(0)
      end
    end
  end
end
