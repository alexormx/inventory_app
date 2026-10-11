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

  describe 'hallazgos de la revisión' do
    it 'un invitado que inicia sesión y sigue usando su carrito no recibe un aviso falso a las 4 h' do
      start = Time.current
      travel_to(start) { post cart_items_path, params: { product_id: product.id } }
      user = create(:user)
      travel_to(start + 5.minutes) do
        sign_in user
        get cart_path
      end
      travel_to(start + 3.hours) { patch cart_item_path(product.id), params: { product_id: product.id, quantity: 2 } }
      travel_to(start + 4.hours + 5.minutes) do
        get cart_path
        expect(response.body).not_to include(notice)
        expect(ShoppingCarts::ActiveCartResolver.find(user)).to be_present
      end
    end

    it 'avisa una vez aunque el job ya haya vencido el carrito, también en el checkout' do
      user = create(:user)
      sign_in user
      post cart_items_path, params: { product_id: product.id }
      ShoppingCarts::ActiveCartResolver.find(user).update_columns(last_activity_at: 5.hours.ago)
      Carts::ExpireIdleCartsJob.perform_now

      get checkout_step1_path
      expect(response).to redirect_to(cart_path)
      expect(flash[:warning]).to eq(notice)
      follow_redirect!
      expect(response.body).to include(notice) # en la página a la que se redirige
      get cart_path
      expect(response.body).not_to include(notice) # y ya no después
    end
  end

  describe 'línea de envío' do
    before do
      ShippingMethod.delete_all
      create(:shipping_method, code: 'envio_estandar', base_cost: 60, active: true)
      sign_in create(:user)
      post cart_items_path, params: { product_id: product.id }
    end

    it 'el cambio de cantidad (JSON) devuelve el texto de envío actualizado' do
      allow(Shipping::Calculator).to receive(:free_shipping?).and_return(false)
      patch cart_item_path(product.id), params: { product_id: product.id, quantity: 2 }, as: :json
      expect(response.parsed_body['shipping_label']).to eq('desde $60')
    end

    it 'quitar un producto actualiza el texto de envío en lugar de "A calcular"' do
      allow(Shipping::Calculator).to receive(:free_shipping?).and_return(false)
      # Un segundo producto para que el carrito no quede vacío y siga el resumen.
      post cart_items_path, params: { product_id: create(:product, selling_price: 100, minimum_price: 100).id }
      delete cart_item_path(product.id), params: { product_id: product.id },
                                         headers: { 'Accept' => 'text/vnd.turbo-stream.html', 'Referer' => 'http://www.example.com/cart' }
      expect(response.body).to include('summary-shipping').and include('desde $60')
      expect(response.body).not_to include('A calcular')
    end
  end
end
