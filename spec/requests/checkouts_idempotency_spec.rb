# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Checkout Idempotency Protection', type: :request do
  let(:user) { create(:user) }
  let(:product) { create(:product, selling_price: 100.0) }
  let(:address) { create(:shipping_address, user: user, default: true) }

  before do
    sign_in user
  end

  # Helper para agregar producto al carrito y configurar sesión de checkout
  def setup_checkout_session
    # Agregar producto al carrito
    post cart_items_path, params: { product_id: product.id, quantity: 2 }
    
    # Configurar dirección y método de envío (step 2)
    post checkout_step2_path, params: {
      selected_address_id: address.id,
      shipping_method: 'standard'
    }
    
    # Visitar step3 para generar el token
    get checkout_step3_path
    
    # Extraer el token generado de la sesión
    # En request specs, la sesión persiste entre requests
    @checkout_token = session[:checkout_token]
  end

  describe 'POST /checkout/complete with idempotency protection' do
    context 'when token is used for the first time' do
      before { setup_checkout_session }

      it 'creates a new sale order successfully' do
        expect {
          post checkout_complete_path, params: {
            payment_method: 'transferencia_bancaria',
            checkout_token: @checkout_token,
            accept_pending: '1'
          }
        }.to change(SaleOrder, :count).by(1)

        expect(response).to redirect_to(checkout_thank_you_path)
        expect(flash[:notice]).to be_present

        order = SaleOrder.last
        expect(order.idempotency_key).to eq(@checkout_token)
        expect(order.user).to eq(user)
      end
    end

    context 'when the same token is reused (duplicate submission)' do
      before do
        setup_checkout_session
        # Crear orden con el mismo token (simular que ya se procesó)
        create(:sale_order, user: user, idempotency_key: @checkout_token)
      end

      it 'does not create a duplicate order' do
        expect {
          post checkout_complete_path, params: {
            payment_method: 'transferencia_bancaria',
            checkout_token: @checkout_token,
            accept_pending: '1'
          }
        }.not_to change(SaleOrder, :count)
      end

      it 'redirects to thank you page with a notice' do
        post checkout_complete_path, params: {
          payment_method: 'transferencia_bancaria',
          checkout_token: @checkout_token,
          accept_pending: '1'
        }
        
        expect(response).to redirect_to(checkout_thank_you_path)
        expect(flash[:notice]).to match(/ya fue procesad/i)
      end
    end

    context 'when token does not match session token' do
      before { setup_checkout_session }

      it 'rejects the request with invalid session error' do
        post checkout_complete_path, params: {
          payment_method: 'transferencia_bancaria',
          checkout_token: 'different-token-123',
          accept_pending: '1'
        }

        expect(response).to redirect_to(checkout_step1_path)
        expect(flash[:alert]).to match(/sesión inválida/i)
      end
    end

    context 'when token is missing' do
      before { setup_checkout_session }

      it 'rejects the request' do
        post checkout_complete_path, params: {
          payment_method: 'transferencia_bancaria',
          accept_pending: '1'
        }

        expect(response).to redirect_to(checkout_step1_path)
        expect(flash[:alert]).to match(/sesión inválida/i)
      end
    end

    context 'when a different token is used' do
      before do
        setup_checkout_session
        # Orden previa con token diferente
        create(:sale_order, user: user, idempotency_key: 'old-token-456')
      end

      it 'creates a new order successfully' do
        expect {
          post checkout_complete_path, params: {
            payment_method: 'transferencia_bancaria',
            checkout_token: @checkout_token,
            accept_pending: '1'
          }
        }.to change(SaleOrder, :count).by(1)

        new_order = SaleOrder.last
        expect(new_order.idempotency_key).to eq(@checkout_token)
        expect(new_order.idempotency_key).not_to eq('old-token-456')
      end
    end
  end

  describe 'Idempotency across multiple users' do
    let(:other_user) { create(:user) }
    let(:other_address) { create(:shipping_address, user: other_user, default: true) }

    it 'allows different users to create orders with their own tokens' do
      # Usuario 1 crea orden
      setup_checkout_session
      first_token = @checkout_token

      post checkout_complete_path, params: {
        payment_method: 'transferencia_bancaria',
        checkout_token: first_token,
        accept_pending: '1'
      }

      first_order = SaleOrder.last
      expect(first_order.user).to eq(user)
      expect(first_order.idempotency_key).to eq(first_token)

      # Usuario 2 con su propio token (nueva sesión)
      sign_out user
      sign_in other_user

      # Configurar carrito y sesión para usuario 2
      post cart_items_path, params: { product_id: product.id, quantity: 1 }
      post checkout_step2_path, params: {
        selected_address_id: other_address.id,
        shipping_method: 'standard'
      }
      get checkout_step3_path
      
      # Extraer el token de la sesión del usuario 2
      second_token = session[:checkout_token]
      
      post checkout_complete_path, params: {
        payment_method: 'efectivo',  # Método de pago válido
        checkout_token: second_token,  # Usando el token generado para este usuario
        accept_pending: '1'
      }
      
      expect(response).to redirect_to(checkout_thank_you_path)
      
      second_order = SaleOrder.last
      expect(second_order.user).to eq(other_user)
      expect(second_order.idempotency_key).to eq(second_token)
      expect(second_token).not_to eq(first_token)  # Los tokens son diferentes
    end
    
    it 'prevents creating duplicate orders even if another user has the same token value' do
      # Este caso es extremadamente improbable en producción (SecureRandom.urlsafe_base64(32))
      # pero lo probamos para verificar que la unicidad está scoped por user
      
      # Usuario 1 crea orden con un token específico
      setup_checkout_session
      shared_token = 'manually-set-token-123'
      
      # Crear orden manualmente con el token compartido
      create(:sale_order, user: user, idempotency_key: shared_token)
      
      # Usuario 2 intenta crear una orden con el MISMO token
      sign_out user
      sign_in other_user
      
      post cart_items_path, params: { product_id: product.id, quantity: 1 }
      post checkout_step2_path, params: {
        selected_address_id: other_address.id,
        shipping_method: 'standard'
      }
      get checkout_step3_path
      
      # Crear orden manualmente para usuario 2 con el mismo token (simula coincidencia)
      order_2 = create(:sale_order, user: other_user, idempotency_key: shared_token)
      
      # Verificar que ambas órdenes existen
      expect(SaleOrder.where(idempotency_key: shared_token).count).to eq(2)
      expect(SaleOrder.where(idempotency_key: shared_token).pluck(:user_id)).to match_array([user.id, other_user.id])
    end
  end
end
